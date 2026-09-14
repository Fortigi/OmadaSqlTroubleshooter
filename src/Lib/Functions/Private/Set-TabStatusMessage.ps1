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

        # Only write when the text actually changes. Issue #119 asks that nothing repaint the bar
        # while no work is in flight. WPF's property system already ignores an equal value (measured:
        # two identical writes raise no Text change), but that is the DependencyProperty's behaviour
        # and not this function's. Callers such as Reset-TabStatusMessage write the steady state
        # again and again, so the guarantee is stated here, where a test can hold it. The tooltip
        # is bound to Text in the XAML and needs nothing from this function.
        if ([string]$Private:StatusBlock.Text -cne [string]$Message) {
            $Private:StatusBlock.Text = $Message
        }

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

function Test-TabStatusMessageTrimmed {
    <#
    .SYNOPSIS
    Tell whether the status bar message is trimmed at the width it has right now.

    .DESCRIPTION
    Issue #119. The one place that decides "is the message cut off". Its only caller is the
    ToolTipOpening handler on TextBlockStatusBarMessage, so the question is asked at hover time,
    against the width the block has at that moment, and never cached.

    It used to be asked when the text was written, and that goes stale. Resizing the window changes
    whether the SAME text trims without anything writing it. Measured in an STA host against this
    markup: "Query 'MvE: Rope log query' executed successfully - see Messages" wants 350px, gets
    725.87px at a 1445px tab and is not trimmed, gets 174px at 700px and is, then gets 725.87px again
    at 1445px, all with no write in between.

    WPF gives nothing to read this from. System.Windows.Controls.TextBlock on .NET 10 has TextTrimming
    and no IsTextTrimmed (reflected in the same host; IsTextTrimmed is WinUI's). So the block is asked
    how wide it wants to be with no constraint, and that is compared with the width it was arranged to.
    The infinite Measure leaves a live element's arrangement invalid until the next layout pass, which
    restores it (measured: DesiredSize 1402px after the call, 720.51px again after UpdateLayout, and
    ActualWidth 725.87px throughout). InvalidateMeasure afterwards makes sure that pass happens.

    .PARAMETER StatusBlock
    The tab's TextBlockStatusBarMessage.

    .OUTPUTS
    $true only when the block has been laid out and its text needs more width than it was given.
    #>
    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        $StatusBlock
    )

    try {
        if ($null -eq $StatusBlock) {
            return $false
        }

        # Before the first layout pass ActualWidth is 0 and nothing is known about what fits. Unknown
        # means "not trimmed": a tooltip cannot open on an element that has not been laid out anyway.
        $Private:AvailableWidth = [double]$StatusBlock.ActualWidth
        if ($Private:AvailableWidth -le 0) {
            return $false
        }

        # Guarded on the method rather than called outright: the headless test lane cannot resolve
        # System.Windows.*, and the stand-in element it passes supplies DesiredSize directly.
        if ($null -ne $StatusBlock.PSObject.Methods["Measure"]) {
            try {
                $StatusBlock.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
            }
            finally {
                $StatusBlock.InvalidateMeasure()
            }
        }

        $Private:NaturalWidth = 0.0
        if ($null -ne $StatusBlock.DesiredSize) {
            $Private:NaturalWidth = [double]$StatusBlock.DesiredSize.Width
        }

        # DesiredSize includes the margin and ActualWidth does not.
        if ($null -ne $StatusBlock.Margin) {
            $Private:NaturalWidth -= [double]$StatusBlock.Margin.Left + [double]$StatusBlock.Margin.Right
        }

        return ($Private:NaturalWidth -gt $Private:AvailableWidth)
    }
    catch {
        "Could not tell whether the status message is trimmed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
        return $false
    }
}

function Confirm-TabStatusMessageToolTipOpening {
    <#
    .SYNOPSIS
    Let the status bar message's tooltip open only while the message is trimmed.

    .DESCRIPTION
    Issue #119. The tooltip itself is declared in MainFormTabContent.xaml, bound to the block's own
    Text, so it always holds the full message and no code ever assigns it. What is left to decide is
    whether it should appear at all, and that is decided here, when WPF is about to open it. A message
    that fits is already on screen, and a tooltip repeating it is noise. Marking ToolTipOpening handled
    cancels the opening.

    .PARAMETER StatusBlock
    The element raising ToolTipOpening, which is the tab's TextBlockStatusBarMessage.

    .PARAMETER EventArguments
    The ToolTipEventArgs of that event.
    #>
    [CmdLetBinding()]
    param(
        $StatusBlock,
        $EventArguments
    )

    if ($null -eq $EventArguments) {
        return
    }

    if (-not (Test-TabStatusMessageTrimmed -StatusBlock $StatusBlock)) {
        $EventArguments.Handled = $true
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
    revert: all three of them - executed successfully, returned no rows, failed (issue #117) - are the
    last real state change on that tab, which is what issue #93 asks the bar to carry, and they stand
    until the next execute.

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
