function New-TemporarySqlQueryObject {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$QueryText
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $TempName = "TMP_$($Script:RunTimeConfig.InstanceGuid)"

        # Every URL and body below comes from New-OmadaQueryRequest, which the background pipeline
        # also uses inside the worker (issue #40, C1-5) - one definition each, so the inline and
        # background paths cannot drift apart.
        $Private:TempContext = @{
            BaseUrl            = $Script:AppConfig.BaseUrl
            TempName           = $TempName
            SelectionText      = $QueryText
            DataConnectionDoId = $Script:AppConfig.CurrentDataConnection.DoId
        }

        try {
            $Private:Probe = New-OmadaQueryRequest -Kind "TempQueryProbe" -Context $Private:TempContext
            $Script:RunTimeData.RestMethodParam.Uri = $Private:Probe.Uri
            $Script:RunTimeData.RestMethodParam.Method = $Private:Probe.Method
            $Script:RunTimeData.RestMethodParam.Body = $Private:Probe.Body
            $ExistingTempQuery = Invoke-OmadaPSWebRequestWrapper

            $RestoreSuccess = $false
            if ($null -ne $ExistingTempQuery -and $null -ne $ExistingTempQuery.Value -and $ExistingTempQuery.Value.Count -gt 0 -and ![string]::IsNullOrWhiteSpace($ExistingTempQuery.Value[0].Id)) {

                if ($ExistingTempQuery.Value[0].Deleted -eq $true) {
                    "Temporary query object with name '{0}' exists. Reuse it." -f $TempName | Write-LogOutput -LogType DEBUG
                    $Private:UndeleteContext = $Private:TempContext.Clone()
                    $Private:UndeleteContext.TempQueryDoId = $ExistingTempQuery.Value[0].Id
                    $Private:Undelete = New-OmadaQueryRequest -Kind "TempQueryUndelete" -Context $Private:UndeleteContext
                    $Script:RunTimeData.RestMethodParam.Uri = $Private:Undelete.Uri
                    $Script:RunTimeData.RestMethodParam.Method = $Private:Undelete.Method
                    $Script:RunTimeData.RestMethodParam.Body = $Private:Undelete.Body
                    $null = Invoke-OmadaPSWebRequestWrapper
                }
                else {
                    "Temporary query object with name '{0}' exists and was not deleted somehow. Reuse it." -f $TempName | Write-LogOutput -LogType DEBUG
                }
                $RestoreSuccess = $true
            }
        }
        catch {
            "Error occurred while checking query object '{0}'" -f $TempName | Write-LogOutput -LogType DEBUG
        }

        if ($RestoreSuccess) {
            "Reusing existing temporary query object with DoId: {0}" -f $ExistingTempQuery.Value[0].Id | Write-LogOutput -LogType DEBUG
            $Private:TempContext.TempQueryDoId = $ExistingTempQuery.Value[0].Id
        }
        else {
            # Reuse the application-wide InstanceGuid (see Initialize-GlobalConfigSettings) for the
            # new object - do NOT generate a fresh guid here. Regenerating meant every tab / every
            # time the temp object was missing produced a brand-new TMP_<guid>, so stale temporary
            # query objects piled up on the server instead of the single shared TMP_<InstanceGuid>
            # being recreated and reused.
            "Temporary query object '{0}' does not exist. Creating it." -f $TempName | Write-LogOutput -LogType DEBUG
            $Private:TempContext.TempQueryDoId = $null
        }

        # PUT when an object was recovered, POST otherwise - the builder decides from TempQueryDoId.
        $Private:Upsert = New-OmadaQueryRequest -Kind "TempQueryUpsert" -Context $Private:TempContext
        $Script:RunTimeData.RestMethodParam.Uri = $Private:Upsert.Uri
        $Script:RunTimeData.RestMethodParam.Method = $Private:Upsert.Method
        $Script:RunTimeData.RestMethodParam.Body = $Private:Upsert.Body

        "Body: {0}" -f (ConvertTo-RedactedLogString -InputObject $Script:RunTimeData.RestMethodParam.Body -ShapeOnly) | Write-LogOutput -LogType VERBOSE
        "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

        $Private:Result = Invoke-OmadaPSWebRequestWrapper
        # A PUT onto a recovered object answers without an Id, so fall back to the id that was
        # reused: it is the object the query has to run against either way. Same rule the pipeline
        # applies in the worker.
        $Private:CreatedDoId = if ($null -ne $Private:Result -and $null -ne $Private:Result.Id) { $Private:Result.Id } else { $Private:TempContext.TempQueryDoId }
        if ($null -ne $Private:CreatedDoId) {
            "Temporary query object ready with DoId: {0}" -f $Private:CreatedDoId | Write-LogOutput -LogType DEBUG
            return $Private:CreatedDoId
        }
        else {
            "Failed to create temporary query object: no Id in response." | Write-LogOutput -LogType ERROR
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        return $null
    }
}
