function Test-WebViewCompletionCallback {
    <#
    .SYNOPSIS
        Reports whether a queued completion callback can actually be invoked with "&".

    .DESCRIPTION
        Items on $Script:PendingWebViewCompletions do not all carry a completion block. A caller
        that only pushes something into the editor and has nothing to do afterwards - the syntax
        pass writing its markers - passes none, and the item is still queued so its task is drained
        and removed.

        Invoking a $null callback fails the whole Tick handler with "The expression after '&' in a
        pipeline element produced an object that was not valid", which takes down the drain loop for
        every other pending item too, not just the one missing a callback.

        Written as a function rather than inline in the timer so the rule is covered by a test. The
        accepted types are exactly what "&" accepts, so a valid callback is never skipped.

    .PARAMETER Callback
        The value taken from the queued item's OnCompletedScriptBlock.

    .OUTPUTS
        [bool] $true when "&" can invoke it, $false when there is nothing to invoke.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Callback
    )

    # No tracer preamble: called for every drained completion, several times a second.

    if ($Callback -is [scriptblock]) {
        return $true
    }

    if ($Callback -is [System.Management.Automation.CommandInfo]) {
        return $true
    }

    return $false
}
