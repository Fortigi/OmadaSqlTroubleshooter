function Resolve-KeyLogAction {
    <#
    .SYNOPSIS
    De-duplicates key events so a held key is logged as exactly one press and one release.

    .DESCRIPTION
    A held key auto-repeats, and the same physical key also arrives twice - once via the window-level
    tunnelling PreviewKeyDown and once via the WebView2 control's own event. WebView2 reconstructs its
    key events without the auto-repeat flag, so IsRepeat cannot be trusted to suppress the flood.

    This tracks, in the supplied state set, which keys are currently "down and logged". It returns:
      - "pressed"  the first time a key goes down (adds it to the set),
      - "released" the first time it comes up   (removes it from the set),
      - $null      for every repeat and for the duplicate down/up from the other event route.

    The caller keeps one long-lived HashSet and only writes a log line when a non-$null action is
    returned. Working on a passed-in set (rather than module state) keeps this unit-testable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyName,
        [Parameter(Mandatory = $true)]
        [bool]$IsRelease,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]   # the state set is empty on the very first key event
        [System.Collections.Generic.HashSet[string]]$State
    )

    if ($IsRelease) {
        # Log a release only once: the first Up for a key recorded as down. Remove returns $false for
        # a repeat Up or the duplicate Up from the other event route.
        if ($State.Remove($KeyName)) {
            return "released"
        }
        return $null
    }

    # Log a press only once per physical hold. Add returns $false when the key is already recorded as
    # down (an auto-repeat, or the duplicate Down from the other event route).
    if ($State.Add($KeyName)) {
        return "pressed"
    }
    return $null
}
