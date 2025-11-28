function Test-OmadaConnection {
    [CmdletBinding()]
    param()

    try {
        "Test connection" | Write-LogOutput -LogType DEBUG
        try {
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $null = Invoke-OmadaPSWebRequestWrapper
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            return $true
        }
        catch {
            "Connection failed with error: {0}! Please check your settings." -f $_.Exception.Message | Write-LogOutput -LogType ERROR
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
            Set-Disconnected
            return $false
        }
    }
    catch {
        return $false
    }
}
