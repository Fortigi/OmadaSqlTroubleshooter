function New-TemporarySqlQueryObject {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$QueryText
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $TempName = "TMP_$($Script:RunTimeConfig.InstanceGuid)"

        try {
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?DeletedStatus=Both&`$filter=NAME eq '{1}'" -f $Script:AppConfig.BaseUrl, $TempName
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $Script:RunTimeData.RestMethodParam.Body = $null
            $ExistingTempQuery = Invoke-OmadaPSWebRequestWrapper

            $RestoreSuccess = $false
            if ($null -ne $ExistingTempQuery -and $null -ne $ExistingTempQuery.Value -and $ExistingTempQuery.Value.Count -gt 0 -and ![string]::IsNullOrWhiteSpace($ExistingTempQuery.Value[0].Id)) {

                if ($ExistingTempQuery.Value[0].Deleted -eq $true) {
                    "Temporary query object with name '{0}' exists. Reuse it." -f $TempName | Write-LogOutput -LogType DEBUG
                    $Script:RunTimeData.RestMethodParam.Uri = "{0}/WebService/DataObjectWebService.asmx/UndeleteDataObject" -f $Script:AppConfig.BaseUrl
                    $Script:RunTimeData.RestMethodParam.Method = "POST"
                    $Script:RunTimeData.RestMethodParam.Body = @{
                        id = $ExistingTempQuery.Value[0].Id
                    } | ConvertTo-Json
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
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $ExistingTempQuery.Value[0].Id
            $Script:RunTimeData.RestMethodParam.Method = "PUT"
        }
        else {
            # Reuse the application-wide InstanceGuid (see Initialize-GlobalConfigSettings) for the
            # new object - do NOT generate a fresh guid here. Regenerating meant every tab / every
            # time the temp object was missing produced a brand-new TMP_<guid>, so stale temporary
            # query objects piled up on the server instead of the single shared TMP_<InstanceGuid>
            # being recreated and reused.
            "Temporary query object '{0}' does not exist. Creating it." -f $TempName | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
            $Script:RunTimeData.RestMethodParam.Method = "POST"
        }

        $Script:RunTimeData.RestMethodParam.Body = @{
            "NAME"    = $TempName
            "C_QUERY" = $QueryText
        }
        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
            $Script:RunTimeData.RestMethodParam.Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{ Id = $Script:AppConfig.CurrentDataConnection.DoId })
        }

        "Body: {0}" -f (ConvertTo-RedactedLogString -InputObject $Script:RunTimeData.RestMethodParam.Body -ShapeOnly) | Write-LogOutput -LogType VERBOSE
        "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

        $Private:Result = Invoke-OmadaPSWebRequestWrapper
        if ($null -ne $Private:Result -and $null -ne $Private:Result.Id) {
            "Temporary query object created with DoId: {0}" -f $Private:Result.Id | Write-LogOutput -LogType DEBUG
            return $Private:Result.Id
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
