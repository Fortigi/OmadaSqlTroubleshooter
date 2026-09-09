function Invoke-OmadaViewLookupPipeline {
    <#
    .SYNOPSIS
    Run both halves of the "SQL Troubleshooting" view lookup - find the view, then fetch its rows -
    as one sequence, and return what the UI needs to apply it.

    .DESCRIPTION
    Issue #90, slice A. Get-SqlTroubleShooterView makes two dependent GetPagingData round-trips: the
    second needs the view id the first returns, so they cannot be fired off in parallel. That pair
    is what Update-DataConnectionList blocks on before it makes its own request, and what
    Update-QueryList blocks on whenever a "my queries" filter is on.

    Two chained background completions would work, and it is deliberately NOT what this is - for the
    reason Invoke-OmadaExecutePipeline gives at greater length and that issue #90 names as the
    dominant risk of this whole slice: between completions, Set-ActiveTabContext can repoint
    $Script:MainForm.Elements, $Script:RunTimeData and $Script:AppConfig onto a different tab. Two
    completions is a smaller version of that defect, not a different one. One background job means
    ONE completion, so the tab-context risk is removed rather than managed.

    Runspace-safe, on the same terms as Invoke-OmadaExecutePipeline: no $Script: reads, no logging,
    no WPF, and no calls into this module beyond New-OmadaPagingRequest and Invoke-OmadaRequestCore,
    which are equally pure. What it cannot do - write the log, touch a dropdown - it does not
    attempt; it returns a description of what happened and the UI thread applies it.

    .PARAMETER Context
    Plain values gathered on the UI thread:
      BaseUrl              the tenant base URL
      Parameters           the prepared Invoke-OmadaRestMethod splat (Uri, Method and Body are
                           overwritten per step; everything else - SessionKey, authentication,
                           redaction - carries)
      IncludeDataObjectHtml  $true to also fetch the dataobjdlg.aspx page for the first row, which is
                           where the data connection options live. This is Update-DataConnectionList's
                           third round-trip, and it is a step of THIS job rather than a second
                           background request chained off this one's completion - for the reason
                           above. Update-QueryList needs only the first two steps and omits it.
      SqlQueryDoIdField    the row property holding the data object id, from
                           $Script:RunTimeData.DataobjdlgAspxAttributeMapping. Passed in because that
                           mapping is UI-thread state. Required when IncludeDataObjectHtml is set.

    .OUTPUTS
    Hashtable:
      Rows           the view's data object rows, or $null when the view was not found
      ViewId         the id of the "SQL Troubleshooting" view, or $null
      ViewFound      $false when the tenant answered but holds no such view - which is a legitimate
                     answer, not a failure, and must not be reported as one
      DataObjectHtml the dataobjdlg.aspx response, when IncludeDataObjectHtml was set and there was
                     a row to fetch it for; otherwise $null
      ErrorRecord    the first failure, or $null
      FailedStep     which step failed, or $null
      CompletedSteps how many requests came back without an error
      Steps          an ordered trace of @{ Name; Method; Uri }
      Log            an ordered list of log entries for the UI thread to replay
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $Outcome = @{
        Rows           = $null
        ViewId         = $null
        ViewFound      = $false
        DataObjectHtml = $null
        ErrorRecord    = $null
        FailedStep     = $null
        Steps          = [System.Collections.Generic.List[object]]::new()
        CompletedSteps = 0
        Log            = [System.Collections.Generic.List[object]]::new()
    }

    # The same two log shapes the execute pipeline uses, for the same reason: redaction
    # (ConvertTo-RedactedLogString) is a UI-thread function and must stay one, so the worker records
    # WHAT to log and the UI thread decides how much of it may be written down.
    $Log = {
        param($Level, $Text)
        $Outcome.Log.Add(@{ Level = $Level; Text = $Text })
    }

    $LogObject = {
        param($Level, $Format, $Object, $ShapeOnly)
        $Outcome.Log.Add(@{ Level = $Level; Format = $Format; Redact = $Object; ShapeOnly = [bool]$ShapeOnly })
    }

    # One local helper rather than a call out to another file: this runs in a worker runspace, and
    # every extra name it depends on is another thing that has to be dot-sourced there.
    $Invoke = {
        param($StepName, $Request)
        $Parameters = $Context.Parameters.Clone()
        $Parameters.Uri = $Request.Uri
        $Parameters.Method = $Request.Method
        if ($null -eq $Request.Body) {
            if ($Parameters.ContainsKey("Body")) { $Parameters.Remove("Body") }
        }
        else {
            $Parameters.Body = $Request.Body
        }

        $Outcome.Steps.Add(@{ Name = $StepName; Method = $Request.Method; Uri = $Request.Uri })

        & $Log "DEBUG" ("QueryUrl: {0}" -f $Request.Uri)
        if ($null -ne $Request.Body) {
            & $LogObject "VERBOSE" "Body: {0}" $Request.Body $true
        }
        & $LogObject "VERBOSE" "Parameters: {0}" $Parameters $false

        $StepOutcome = Invoke-OmadaRequestCore -Parameters $Parameters

        if ($null -eq $StepOutcome.ErrorRecord) {
            $Outcome.CompletedSteps = $Outcome.CompletedSteps + 1
            & $LogObject "VERBOSE" "Result: {0}" $StepOutcome.Result $false
        }
        else {
            # DEBUG, not ERROR: the pipeline reports its failure through the outcome, and the caller
            # decides how loudly to say so. An ERROR written from here would be written twice.
            & $Log "DEBUG" ("Step '{0}' failed: {1}" -f $StepName, $StepOutcome.ErrorRecord.Exception.Message)
        }
        return $StepOutcome
    }

    try {
        # --- 1. Find the "SQL Troubleshooting" view ------------------------------------------------
        & $Log "DEBUG" "Retrieve data connections"

        $Private:ViewLookup = & $Invoke "FindView" (New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{ OwnerShipType = "Both" } -SearchString "SQL Troubleshooting" -BaseUrl $Context.BaseUrl)
        if ($null -ne $Private:ViewLookup.ErrorRecord) {
            $Outcome.ErrorRecord = $Private:ViewLookup.ErrorRecord
            $Outcome.FailedStep = "FindView"
            return $Outcome
        }

        # Records greater than zero before reading Rows, exactly as Get-SqlTroubleShooterView has
        # always checked. The search is a contains-match on the name, so the result may hold other
        # views; the exact-name filter is what picks this one out.
        $Private:View = $null
        if ($null -ne $Private:ViewLookup.Result -and $Private:ViewLookup.Result.d.Records -gt 0) {
            $Private:View = $Private:ViewLookup.Result.d.Rows | Where-Object { $_.Name -eq "SQL Troubleshooting" } | Select-Object -First 1
        }

        if ($null -eq $Private:View) {
            # A tenant without the view is not a failed request. Reporting it through ErrorRecord
            # would send the caller down the retry-on-the-UI-thread path, which would ask the same
            # question again and get the same answer.
            & $Log "DEBUG" "The 'SQL Troubleshooting' view was not found."
            return $Outcome
        }

        $Outcome.ViewFound = $true
        $Outcome.ViewId = $Private:View.Id

        # --- 2. Fetch the view's rows ---------------------------------------------------------------
        $Private:RowRequest = New-OmadaPagingRequest -DataType "DataObjects" -BaseUrl $Context.BaseUrl -DataTypeArgs ([ordered]@{
                viewId          = ("{0}" -f $Private:View.Id)
                pageQueryString = ("{0}/dataobjlst.aspx?view={1}" -f $Context.BaseUrl, $Private:View.Id)
                readOnlyMode    = $false
                countRows       = $false
            })

        $Private:Rows = & $Invoke "FetchViewRows" $Private:RowRequest
        if ($null -ne $Private:Rows.ErrorRecord) {
            $Outcome.ErrorRecord = $Private:Rows.ErrorRecord
            $Outcome.FailedStep = "FetchViewRows"
            return $Outcome
        }

        $Outcome.Rows = $Private:Rows.Result.d.Rows

        # --- 3. The data connection page, when the caller wants it ---------------------------------
        if (-not $Context.IncludeDataObjectHtml) {
            return $Outcome
        }

        $Private:FirstRow = @($Outcome.Rows) | Select-Object -First 1
        if ($null -eq $Private:FirstRow) {
            # No rows means no data object to open, which Update-DataConnectionList already treats as
            # "cannot change the data connection". Not an error.
            & $Log "DEBUG" "The SQL Troubleshooting view returned no rows; no data connection page to fetch."
            return $Outcome
        }

        $Private:DataObjectId = $Private:FirstRow.$($Context.SqlQueryDoIdField)

        $Private:Html = & $Invoke "FetchDataConnectionPage" (@{
                Method = "GET"
                Uri    = "{0}/dataobjdlg.aspx?DOID={1}" -f $Context.BaseUrl, $Private:DataObjectId
                Body   = $null
            })
        if ($null -ne $Private:Html.ErrorRecord) {
            $Outcome.ErrorRecord = $Private:Html.ErrorRecord
            $Outcome.FailedStep = "FetchDataConnectionPage"
            return $Outcome
        }

        $Outcome.DataObjectHtml = $Private:Html.Result
        return $Outcome
    }
    catch {
        # A throw from here would surface as a worker that died rather than as an answer, and the
        # caller cannot classify that. Report it the same way a failed step is reported.
        $Outcome.ErrorRecord = $_
        if ($null -eq $Outcome.FailedStep) {
            $Outcome.FailedStep = "ViewLookup"
        }
        return $Outcome
    }
}
