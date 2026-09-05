function Build-OmadaRequestParameter {
    <#
    .SYNOPSIS
    Turn the active tab's $Script:RunTimeData.RestMethodParam into the splat Invoke-OmadaRestMethod
    is actually called with. UI thread only.

    .DESCRIPTION
    Extracted from Invoke-OmadaPSWebRequestWrapper so the synchronous and the background paths
    prepare a request identically - one copy of these rules, not two that drift (issue #40).

    It reads $Script:RunTimeConfig and $Script:SkipBodyRedaction, so it belongs on the UI thread; the
    result is a plain hashtable that a worker can be handed a clone of.

    Note that this mutates $Script:RunTimeData.RestMethodParam in place and returns it, exactly as
    the wrapper always did. Callers that dispatch it to a worker must clone it first - that hashtable
    is long-lived and the next call site overwrites Uri, Method and Body.

    .OUTPUTS
    The prepared parameter hashtable.
    #>
    [CmdletBinding()]
    param()

    $Private:Parameters = $Script:RunTimeData.RestMethodParam

    $Private:Parameters.UseWebView2 = $Private:Parameters.AuthenticationType -eq "Browser" ? $($Script:RunTimeConfig.UseWebView2Auth) : $false

    # ForceAuthentication is passed ONLY when it is actually true, and this is not cosmetic.
    #
    # OmadaWeb.PS decides whether to load its encrypted cookie cache with
    # "$BoundParams.Keys -notcontains 'ForceAuthentication'" - it tests whether the parameter was
    # BOUND, not what it was set to. This application has always splatted ForceAuthentication = $false
    # on every request, so that test was always false and the cookie cache was never read by anyone,
    # ever. On the UI thread that is invisible: the module's in-memory session already holds the
    # cookie after the first authentication.
    #
    # It stopped being invisible when requests moved to a worker runspace (issue #40). A worker has
    # its own OmadaWeb.PS instance with an empty session table, so with the cache unreadable it had no
    # choice but to authenticate - and an interactive WebView2 login in an MTA worker fails with
    # "Couldn't find a compatible Webview2 Runtime installation to host WebViews". That was every
    # background request on a live tenant.
    #
    # Removing the key restores the behaviour the cache was written for: a fresh runspace picks up the
    # session the UI thread established. A genuinely stale cookie still fails safely - Test-OmadaConnection
    # retries with ForceAuthentication = $true, which binds the parameter and forces a real login.
    if ($true -ne $Private:Parameters.ForceAuthentication) {
        if ($Private:Parameters.ContainsKey("ForceAuthentication")) {
            $Private:Parameters.Remove("ForceAuthentication")
        }
    }

    if ($null -eq $Private:Parameters.Body) {
        if ($Private:Parameters.ContainsKey("Body")) {
            $Private:Parameters.Remove("Body")
        }
    }
    else {
        if (!$Private:Parameters.ContainsKey("Body")) {
            $Private:Parameters.Add("Body", $null)
        }
    }

    # Keep the module's own verbose stream in step with this application's log, so the two do not
    # contradict each other on the same request. Passed only when the installed OmadaWeb.PS actually
    # declares the parameter: -SkipBodyRedaction is newer than the pinned minimum version, and
    # splatting a parameter a cmdlet does not have is a terminating error. Capability-checked rather
    # than version-gated, so this works the day the switch ships without forcing everyone onto a
    # release that does not exist yet.
    $Private:RestMethodCommand = Get-Command -Name Invoke-OmadaRestMethod -ErrorAction SilentlyContinue
    if ($null -ne $Private:RestMethodCommand -and $Private:RestMethodCommand.Parameters.ContainsKey("SkipBodyRedaction")) {
        $Private:Parameters.SkipBodyRedaction = [bool]$Script:SkipBodyRedaction
    }
    elseif ($Private:Parameters.ContainsKey("SkipBodyRedaction")) {
        # The installed module was downgraded mid-session; drop the key rather than fail.
        $Private:Parameters.Remove("SkipBodyRedaction")
    }

    return $Private:Parameters
}
