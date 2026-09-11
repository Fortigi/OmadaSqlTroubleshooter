function Set-TabStatusMessage {
    <#
    .SYNOPSIS
    Write the most recent state change to a tab's status bar.

    .DESCRIPTION
    The single writer of the status bar's stretchy first column, which carries whatever happened
    last on this tab: connecting, connected, executing, executed, failed. It replaced both the
    floating popup windows (issue #93) and the separate "Disconnected" block that used to own this
    column - connection changes are themselves state changes, so they belong in the same place as
    the rest rather than competing with them for the only column that can grow.

    Addressed to a tab, never to "the UI". Since queries run in the background (issue #40) a
    completion can arrive while the user is looking at a different tab, and $Script:MainForm.Elements
    points at whichever tab Set-ActiveTabContext last made current - so writing through that would
    put one tab's progress on another tab's status bar. Writing through the tab session's OWN
    Elements cannot do that whatever the user switches to meanwhile. Update-BackgroundRequestElapsedTime
    shares this column and reaches it the same way, for the same reason.

    A single entry point is also what makes the status bar auditable. Issue #71 is open precisely
    because a second, unidentified writer of this text block was never found; with one function there
    is one place to look.

    .PARAMETER Message
    The state change to show. Replaces whatever was there - the bar carries the latest state, not a
    history. The detail belongs in the Messages tab (see Add-TabMessage).

    .PARAMETER TabSession
    The tab whose status bar to write. Defaults to the active tab, which during a background
    completion is the tab the work belongs to: the completion poll timer steps into the owning tab
    before invoking the completion.

    .PARAMETER Render
    Pump the dispatcher once so the message is actually on screen before returning. Set it when the
    very next thing the caller does is block the UI thread - opening a tab, refreshing the query
    list - because otherwise the message is queued behind work that never yields, the bar still shows
    the previous state for the whole freeze, and the application looks hung rather than busy. The
    popup windows this replaced pumped for exactly the same reason.

    Not the default: a completion writing its result has nothing to block on, and pumping the
    dispatcher where it is not needed invites the reentrancy Suspend-WebViewCompletionPolling exists
    to prevent.
    #>
    [CmdLetBinding()]
    param(
        [string]$Message,
        $TabSession,
        [switch]$Render
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.Elements) {
            return
        }

        $Private:StatusBlock = $Private:Target.Elements.TextBlockStatusBarMessage
        if ($null -eq $Private:StatusBlock) {
            return
        }

        $Private:StatusBlock.Text = $Message

        if ($Render -and $null -ne $Private:StatusBlock.Dispatcher) {
            $Private:StatusBlock.Dispatcher.Invoke([System.Action] {}, [System.Windows.Threading.DispatcherPriority]::Render) | Out-Null
        }
    }
    catch {
        # A status bar that cannot be painted must not take the operation it was describing down
        # with it. The message is already in the log by the time this runs.
        "Could not write the status message: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Reset-TabStatusMessage {
    <#
    .SYNOPSIS
    Return a tab's status bar to its steady state: whether the tab is connected.

    .DESCRIPTION
    Not every message is worth keeping once the thing it describes is over. "Refreshing queries...",
    "Updating data connections...", "Opening tab 'X'..." are progress, and leaving "Queries refreshed"
    on the bar afterwards means the one question the bar has always answered - am I connected? - is
    answered by something else entirely, for as long as the user does not run a query.

    So transient operations revert here and the connection state comes back. A query OUTCOME does not
    revert: "executed successfully" and "completed with errors" are the last real state change on that
    tab, which is what issue #93 asks the bar to carry, and they stand until the next execute.

    This is also why column 0 could absorb the connection state in the first place. It is not that
    connection state stopped mattering - it is that it became the thing the bar falls back to.

    .PARAMETER TabSession
    The tab whose status bar to reset. Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target) {
            return
        }

        # The tab's own flag, not $Script:ConnectionStatus: that one follows the active tab, and a
        # tab finishing a refresh in the background must report its OWN state rather than the state
        # of whatever the user has since switched to.
        $Private:Text = if ($Private:Target.ConnectionStatus) { "Connected" } else { "Disconnected" }
        Set-TabStatusMessage -TabSession $Private:Target -Message $Private:Text
    }
    catch {
        "Could not reset the status message: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
