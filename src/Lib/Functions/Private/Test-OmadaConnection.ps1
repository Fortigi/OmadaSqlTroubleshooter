function Test-OmadaConnection {
    [CmdletBinding()]
    param()

    try {
        "Test connection" | Write-LogOutput -LogType DEBUG
        try {
            # Key the OmadaWeb.PS session by connection identity rather than the unique tab id, so
            # tabs with the same tenant/auth/credentials share one authenticated session (a second
            # matching tab connects without its own login prompt).
            # Get-TabConnectionIdentity's Key is a SHA256 hash and is never empty/whitespace even
            # when every identity field is blank, so checking only Key would always overwrite the
            # tab's own default SessionKey (its TabId, set in New-TabSession) - including for tabs
            # with no configured identity, which would then spuriously share a session bucket with
            # every other unconfigured tab. Gate on IsEmpty, which is computed specifically to
            # distinguish that case, so sharing only happens when there's an actual identity to share.
            $ConnectionIdentity = Get-TabConnectionIdentity -TabSession (Get-ActiveTabSession)
            if ($null -ne $ConnectionIdentity -and !$ConnectionIdentity.IsEmpty -and ![string]::IsNullOrWhiteSpace($ConnectionIdentity.Key)) {
                $Script:RunTimeData.RestMethodParam.SessionKey = $ConnectionIdentity.Key
            }

            # InPrivate signs in again once per application run, per session. Since issue #40 the
            # app leaves ForceAuthentication unbound so a worker can load OmadaWeb.PS's encrypted
            # on-disk cookie - and OmadaWeb.PS loads that cookie whatever -InPrivate says, so an
            # InPrivate tab reconnected after a restart without ever showing a login. Forcing it on
            # the FIRST connect of the run restores the prompt; the fresh cookie is cached again, so
            # later tabs on the same session and the background workers reuse it.
            $Private:SessionKey = [string]$Script:RunTimeData.RestMethodParam.SessionKey
            $Private:IsInPrivate = $true -eq $Script:RunTimeData.RestMethodParam.InPrivate
            if ($null -eq $Script:InPrivateSignedInSessionKeys) {
                $Script:InPrivateSignedInSessionKeys = [System.Collections.Generic.HashSet[string]]::new()
            }

            if ($Private:IsInPrivate -and -not $Script:InPrivateSignedInSessionKeys.Contains($Private:SessionKey)) {
                "InPrivate: signing in again for this application run." | Write-LogOutput -LogType DEBUG
                $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
            }

            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $null = Invoke-OmadaPSWebRequestWrapper
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            $Script:RunTimeData.AuthenticationRetryCount = 0

            # Only a successful sign-in counts: a failed one leaves the key out, so the next connect
            # prompts again.
            if ($Private:IsInPrivate) {
                [void]$Script:InPrivateSignedInSessionKeys.Add($Private:SessionKey)
            }

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
