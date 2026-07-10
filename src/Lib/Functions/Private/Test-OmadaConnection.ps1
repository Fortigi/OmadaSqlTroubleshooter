function Test-OmadaConnection {
    [CmdletBinding()]
    param()

    try {
        "Test connection" | Write-LogOutput -LogType DEBUG
        try {
            # Key the OmadaWeb.PS session by connection identity rather than the unique tab id, so
            # tabs with the same tenant/auth/credentials share one authenticated session (a second
            # matching tab connects without its own login prompt).
            $ConnectionIdentity = Get-TabConnectionIdentity -TabSession (Get-ActiveTabSession)
            if ($null -ne $ConnectionIdentity -and ![string]::IsNullOrWhiteSpace($ConnectionIdentity.Key)) {
                $Script:RunTimeData.RestMethodParam.SessionKey = $ConnectionIdentity.Key
            }

            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $null = Invoke-OmadaPSWebRequestWrapper
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            $Script:RunTimeData.AuthenticationRetryCount = 0
            return $true
        }
        catch {
            # OmadaWeb.PS already retries the underlying request internally (3x) before this catch
            # is reached, so this app must add at most ONE forced re-authentication for a stale
            # cached session (401) and then give up - otherwise the login popup loops forever.
            # The counter MUST be the per-tab $Script:RunTimeData.AuthenticationRetryCount (created
            # per tab in New-TabSession), not the process-global $Script:RunTimeConfig one, which
            # was uninitialized and let one tab's failures suppress or amplify another's.
            $Script:RunTimeData.AuthenticationRetryCount++
            if ($Script:RunTimeData.AuthenticationRetryCount -le 1 -and $_.Exception.Response?.StatusCode -eq 401) {
                $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
                return Test-OmadaConnection
            }

            "Connection failed with error: {0}! Please check your settings." -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            # Give up cleanly: reset this tab's retry budget and do NOT re-arm ForceAuthentication,
            # so the next explicit Connect click starts one clean attempt instead of immediately
            # forcing another interactive login (which is what made the retries "never stop").
            $Script:RunTimeData.AuthenticationRetryCount = 0
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            Set-SqlConnectionState -Status $false
            return $false
        }
    }
    catch {
        return $false
    }
}
