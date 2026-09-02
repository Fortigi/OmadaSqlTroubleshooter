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
