function Invoke-OmadaSqlSchemaPipeline {
    <#
    .SYNOPSIS
    Fetch a database's SQL schema and build what the UI needs from it - the editor's JSON and the
    validation index - in the background worker, rather than on the UI thread when it lands.

    .DESCRIPTION
    A schema request used to be a single background request, and everything derived from the response
    was built when it reached the UI thread: the editor model serialised to JSON (0.1-0.5 s per
    database on a cloud PC) and the validation pass's index (0.2-0.3 s). With five databases preloaded
    on connect, that was about two seconds of frozen window for work that needs no window at all.

    Runspace-safe, on the same terms as Invoke-OmadaViewLookupPipeline: no $Script: reads, no logging,
    no WPF, and no calls into this module beyond Invoke-OmadaRequestCore, ConvertTo-SqlSchemaEditorModel
    and Get-SqlSchemaModel -NoLog, which are equally pure. What it records for the log it leaves in
    Log, for the UI thread to replay through Write-ExecutePipelineLog.

    THE DERIVED VALUES ARE AN OPTIMISATION, NEVER A REQUIREMENT. Each is built in its own try: one that
    fails is left $null, and the UI thread builds it exactly as it did before this existed. Only the
    response decides whether the schema was retrieved.

    .PARAMETER Context
    Plain values gathered on the UI thread:
      Parameters  the prepared Invoke-OmadaRestMethod splat for the GetSqlSchema request (Uri, Method
                  and Body already set), which Start-OmadaBackgroundRequest puts here

    .OUTPUTS
    Hashtable:
      IsSqlSchemaPipeline  $true - how the completion tells this outcome from a plain response
      Result               the response, or $null when the request failed
      ErrorRecord          the failure, or $null
      EditorJson           the editor's compact JSON for this schema, or $null
      SchemaModel          the validation index (Get-SqlSchemaModel's shape), or $null
      Log                  entries for Write-ExecutePipelineLog
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $Outcome = @{
        IsSqlSchemaPipeline = $true
        Result              = $null
        ErrorRecord         = $null
        EditorJson          = $null
        SchemaModel         = $null
        Log                 = [System.Collections.Generic.List[object]]::new()
    }

    $Core = Invoke-OmadaRequestCore -Parameters $Context.Parameters
    if ($null -ne $Core.ErrorRecord) {
        $Outcome.ErrorRecord = $Core.ErrorRecord
        $Outcome.Log.Add(@{ Level = "DEBUG"; Text = ("The SQL schema request failed: {0}" -f $Core.ErrorRecord.Exception.Message) })
        return $Outcome
    }

    $Outcome.Result = $Core.Result
    # Recorded, not formatted: redaction is a UI-thread function, and Write-ExecutePipelineLog decides how
    # much of the response the log level may show.
    $Outcome.Log.Add(@{ Level = "VERBOSE"; Format = "Result: {0}"; Redact = $Core.Result; ShapeOnly = $false })

    if ($null -eq $Core.Result -or $null -eq $Core.Result.d) {
        return $Outcome
    }

    try {
        $Outcome.EditorJson = ConvertTo-SqlSchemaEditorModel -SchemaResponse $Core.Result | ConvertTo-Json -Depth 5 -Compress
    }
    catch {
        $Outcome.Log.Add(@{ Level = "DEBUG"; Text = ("The editor model could not be built in the background; the UI thread will build it. {0}" -f $_.Exception.Message) })
    }

    try {
        $Outcome.SchemaModel = Get-SqlSchemaModel -SchemaResponse $Core.Result -NoLog
    }
    catch {
        $Outcome.Log.Add(@{ Level = "DEBUG"; Text = ("The validation index could not be built in the background; the UI thread will build it. {0}" -f $_.Exception.Message) })
    }

    return $Outcome
}
