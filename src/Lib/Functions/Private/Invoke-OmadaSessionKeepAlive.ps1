function Invoke-OmadaSessionKeepAlive {
    <#
    .SYNOPSIS
    Keep each connected tenant session alive with a periodic, silent request.

    .DESCRIPTION
    Issue #89. An Omada session cookie expires in roughly ten minutes. Left alone, an application
    that is open but idle loses its session without anything on screen changing, and the user finds
    out at the worst moment - part-way through running something.

    This was measured rather than assumed. In the live session that answered "does background
    execution survive?" the application ran five queries in nine minutes, sat idle for seventy, and
    the first query after the idle failed: the session had gone, and a worker cannot sign in to get
    it back. That is the failure this exists to prevent.

    Three properties make it safe to run on a timer:

    It cannot prompt. The request is made with OmadaWeb.PS's -NoInteractiveAuthentication - requested
    for this in Fortigi/OmadaWeb.PS#84 and added by Fortigi/OmadaWeb.PS#85 - under which no code path
    can open a browser, a WebView2 window or any other sign-in. Without that switch a keep-alive
    would be the worst possible thing to run unattended: a login window appearing over whatever the
    user is doing, at a moment they did not choose. With it, an expired session is a catchable error
    instead.

    It is silent. Everything here logs at DEBUG and no path raises a dialog. A keep-alive the user
    notices has failed at its job.

    It gives up rather than retries. A session that cannot be revived is not going to be revived by
    asking again in five minutes, so that session key is dropped. The alternative is a request every
    interval, forever, against a tenant that has already said no.

    Giving up is NOT permanent, and that distinction matters. The abandonment is keyed by SessionKey,
    which is a stable hash of the connection identity - so it is the same key after the user signs in
    again. Left alone, one expiry would switch the keep-alive off for that tenant and identity for
    the rest of the application's life, which is precisely the failure the keep-alive exists to
    prevent. Set-SqlConnectionState clears it through Reset-SessionKeepAlive the moment a tab is
    connected again.

    .NOTES
    Runs on the UI thread, deliberately. A worker runspace has its OWN OmadaWeb.PS session context,
    so keeping a worker's session alive would do nothing for the session the user's queries actually
    use. The cost is one small GET per connected tenant every few minutes.

    Driven from $Script:WebViewCompletionPollTimer rather than a timer of its own, for the same
    reasons as the elapsed-time indicator: that timer is already the single place that knows about
    pending work and is already suspended around modal dialogs.

    Pings once per SESSION, not once per tab. Tabs that share a SessionKey share one OmadaWeb.PS
    session, so a ping for one serves all of them; per-tab would multiply requests against the tenant
    for no benefit.

    What it deliberately does NOT do is mark a tab disconnected when the session has gone, which the
    issue's acceptance criteria suggested. Set-SqlConnectionState writes into
    $Script:MainForm.Elements - the ACTIVE tab's element bag - so doing that for a background tab
    needs a full Set-ActiveTabContext round trip, and flipping a tab to "Disconnected" from a timer
    while the user is typing in it is a larger behaviour change than a keep-alive should make on its
    own. The existing re-authentication path already handles the next real request. See the PR.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Private:IntervalMinutes = Get-SessionKeepAliveInterval
        if ($Private:IntervalMinutes -le 0) {
            return
        }

        $Private:Now = [DateTime]::UtcNow
        if ($null -ne $Script:LastSessionKeepAliveUtc -and ($Private:Now - $Script:LastSessionKeepAliveUtc).TotalMinutes -lt $Private:IntervalMinutes) {
            return
        }

        # Stamped BEFORE the requests, not after. These are synchronous, so a slow or hanging tenant
        # would otherwise let the next tick start a second round on top of the first.
        $Script:LastSessionKeepAliveUtc = $Private:Now

        if ($null -eq $Script:SessionKeepAliveAbandoned) {
            $Script:SessionKeepAliveAbandoned = @{}
        }

        # One ping per distinct session, not per tab.
        $Private:Seen = @{}
        foreach ($Private:Tab in @($Script:Tabs)) {
            if ($null -eq $Private:Tab -or -not $Private:Tab.ConnectionStatus) {
                continue
            }

            $Private:SessionKey = $Private:Tab.RunTimeData.RestMethodParam.SessionKey
            if ([string]::IsNullOrWhiteSpace($Private:SessionKey) -or $Private:Seen.ContainsKey($Private:SessionKey)) {
                continue
            }
            $Private:Seen[$Private:SessionKey] = $true

            if ($Script:SessionKeepAliveAbandoned.ContainsKey($Private:SessionKey)) {
                continue
            }

            Invoke-OmadaSessionKeepAlivePing -TabSession $Private:Tab
        }
    }
    catch {
        # A keep-alive that cannot run is not worth telling the user about: their next real request
        # will sign in normally. Reported at DEBUG so it is still findable in a log.
        "Session keep-alive failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Reset-SessionKeepAlive {
    <#
    .SYNOPSIS
    Allow the keep-alive to resume for a session that has been signed into again.

    .DESCRIPTION
    Called from Set-SqlConnectionState when a tab becomes connected. Without it the abandonment in
    Invoke-OmadaSessionKeepAlivePing is permanent for the life of the application: it is keyed by
    SessionKey, which is a stable hash of the connection identity, so signing in again produces the
    SAME key and the keep-alive would stay switched off for that tenant and identity - leaving the
    user exposed to exactly the silent expiry this feature exists to prevent.

    Clears every abandoned session rather than one, deliberately. A successful sign-in usually means
    the credentials or the network came back, which is as likely to have fixed the others; and the
    cost of being wrong is one cheap request per session at the next interval, which then abandons
    again.

    The interval timer is reset too, so a tab that has just connected is not pinged seconds later.
    #>
    [CmdLetBinding()]
    param()

    $Script:SessionKeepAliveAbandoned = @{}
    $Script:LastSessionKeepAliveUtc = [DateTime]::UtcNow
}

function Invoke-OmadaSessionKeepAlivePing {
    <#
    .SYNOPSIS
    Make the single silent request that keeps one tenant session alive.

    .PARAMETER TabSession
    A connected tab whose session is to be refreshed. Its own RestMethodParam supplies the tenant,
    the authentication type and the session key, so the ping is made exactly as that tab's real
    requests are.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    $Private:SessionKey = $TabSession.RunTimeData.RestMethodParam.SessionKey

    try {
        # A CLONE. $Script:RunTimeData.RestMethodParam is overwritten by whatever request a tab makes
        # next, and this one belongs to a tab that may not even be on screen.
        $Private:Parameters = $TabSession.RunTimeData.RestMethodParam.Clone()

        # $top=1 so the tenant does not compose a full query list every few minutes for an answer
        # nobody reads. What matters is that the request is authenticated and reaches Omada.
        $Private:Parameters.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$top=1" -f $TabSession.AppConfig.BaseUrl
        $Private:Parameters.Method = "GET"
        $Private:Parameters.Remove("Body")

        # The switch this whole feature waited for: no path under it can open a sign-in.
        $Private:Parameters.NoInteractiveAuthentication = $true

        # OmadaWeb.PS refuses the two together, and rightly: one forbids signing in, the other
        # requires it. The tab's parameters may still carry it from an earlier forced login.
        if ($Private:Parameters.ContainsKey("ForceAuthentication")) {
            $Private:Parameters.Remove("ForceAuthentication")
        }

        $Private:Outcome = Invoke-OmadaRequestCore -Parameters $Private:Parameters

        if ($null -eq $Private:Outcome.ErrorRecord) {
            "Session keep-alive succeeded for '{0}'." -f $TabSession.AppConfig.BaseUrl | Write-LogOutput -LogType DEBUG
            return
        }

        if (Test-OmadaSessionExpiredError -ErrorRecord $Private:Outcome.ErrorRecord) {
            # Gone, and not coming back on its own. Asking again every interval would be a request
            # per interval for the rest of the session against a tenant that has already refused.
            $Script:SessionKeepAliveAbandoned[$Private:SessionKey] = $true
            "Session keep-alive stopped for '{0}': the session has expired and cannot be renewed without signing in." -f $TabSession.AppConfig.BaseUrl | Write-LogOutput -LogType DEBUG
            return
        }

        # Anything else - a 502, a network blip - says nothing about the session, so the next
        # interval tries again.
        "Session keep-alive request failed for '{0}': {1}" -f $TabSession.AppConfig.BaseUrl, $Private:Outcome.ErrorRecord.Exception.Message | Write-LogOutput -LogType DEBUG
    }
    catch {
        "Session keep-alive failed for '{0}': {1}" -f $TabSession.AppConfig.BaseUrl, $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
