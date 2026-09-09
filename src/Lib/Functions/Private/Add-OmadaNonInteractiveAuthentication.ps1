function Add-OmadaNonInteractiveAuthentication {
    <#
    .SYNOPSIS
    Return a copy of a request splat that can use the existing session but can never sign in.

    .DESCRIPTION
    For requests made on a background worker. A worker has no desktop and its pool is MTA on purpose,
    so an interactive sign-in there cannot succeed - it fails as a WebView2RuntimeNotFoundException,
    which is exactly what a live session showed: after a seventy-minute idle the session had expired,
    the worker tried to sign in, and background execution switched itself off for the rest of the
    session.

    -NoInteractiveAuthentication (Fortigi/OmadaWeb.PS#85) makes that impossible. No code path under it
    can open a browser, a WebView2 window or any other prompt, and an expired or missing session comes
    back as a typed error instead - which Test-OmadaSessionExpiredError recognises and
    Resolve-ExecuteFallbackAction can then classify properly, rather than guessing from the text of a
    WebView2 exception.

    Two things this deliberately handles:

    ForceAuthentication is removed. OmadaWeb.PS refuses the two together, and rightly - one forbids
    signing in, the other requires it - so a splat carrying it from an earlier forced login would fail
    every background request outright.

    The switch is only added when the installed OmadaWeb.PS actually has it. PowerShell REJECTS an
    unknown parameter rather than ignoring it, so passing it to an older module would break every
    background request instead of degrading. The application's minimum is 2026.07.09.9, which predates
    the switch, so this is a real case and not a theoretical one. Same shape as the SkipBodyRedaction
    capability check in Build-OmadaRequestParameter.

    On an older module the caller simply gets the splat back unchanged: the worker behaves exactly as
    it did before, including the WebView2 failure, which Resolve-ExecuteFallbackAction still
    recognises by message.

    .PARAMETER Parameters
    The prepared splat. Not mutated - a copy is returned, because the caller's hashtable is the live
    one the next request is built from.

    .OUTPUTS
    [hashtable] a copy, safe to hand to a worker.
    #>
    [CmdLetBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    $Private:Result = $Parameters.Clone()

    try {
        if (-not (Test-OmadaRestMethodParameter -Name "NoInteractiveAuthentication")) {
            # Older module. Leave the splat alone rather than send a parameter it will reject.
            if ($Private:Result.ContainsKey("NoInteractiveAuthentication")) {
                $Private:Result.Remove("NoInteractiveAuthentication")
            }

            return $Private:Result
        }

        $Private:Result.NoInteractiveAuthentication = $true

        if ($Private:Result.ContainsKey("ForceAuthentication")) {
            $Private:Result.Remove("ForceAuthentication")
        }
    }
    catch {
        # A capability check that cannot run must not stop the query. The worst case is the behaviour
        # this function was written to improve, which the fallback classification already handles.
        "Could not determine whether OmadaWeb.PS supports -NoInteractiveAuthentication: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }

    return $Private:Result
}
