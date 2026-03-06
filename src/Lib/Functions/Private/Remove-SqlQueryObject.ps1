function Remove-SqlQueryObject {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DoId
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        "Deleting query object with DoId: {0}" -f $DoId | Write-LogOutput -LogType DEBUG

        $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $DoId
        $Script:RunTimeData.RestMethodParam.Method = "DELETE"
        $Script:RunTimeData.RestMethodParam.Body = $null

        "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

        Invoke-OmadaPSWebRequestWrapper | Out-Null
        "Query object {0} deleted successfully." -f $DoId | Write-LogOutput -LogType DEBUG
    }
    catch {
        "Failed to delete query object {0}: {1}" -f $DoId, $_.Exception.Message | Write-LogOutput -LogType WARNING
    }
}
