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
            $Script:RunTimeConfig.AuthenticationRetryCount = 0
            return $true
        }
        catch {
            $Script:RunTimeConfig.AuthenticationRetryCount++
            if ($Script:RunTimeConfig.AuthenticationRetryCount -le 1 -and $_.Exception.Response.StatusCode -eq 401) {
                $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
                return Test-OmadaConnection
            }

            "Connection failed with error: {0}! Please check your settings." -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
            Set-SqlConnectionState -Status $false
            return $false
        }
    }
    catch {
        return $false
    }
}
