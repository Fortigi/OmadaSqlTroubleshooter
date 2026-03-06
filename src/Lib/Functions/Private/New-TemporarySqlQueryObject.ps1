function New-TemporarySqlQueryObject {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$QueryText
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $TempName = "TMP_$(([System.Guid]::NewGuid()).ToString('N'))"
        "Creating temporary query object with name: {0}" -f $TempName | Write-LogOutput -LogType DEBUG

        $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
        $Script:RunTimeData.RestMethodParam.Method = "POST"
        $Script:RunTimeData.RestMethodParam.Body = @{
            "NAME"    = $TempName
            "C_QUERY" = $QueryText
        }
        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
            $Script:RunTimeData.RestMethodParam.Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{ Id = $Script:AppConfig.CurrentDataConnection.DoId })
        }

        "Body: {0}" -f ($Script:RunTimeData.RestMethodParam.Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
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
