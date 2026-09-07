function Add-TabScopedMessage {
    <#
    .SYNOPSIS
    Hold a tab-scoped warning or error until the tab it belongs to is on screen.

    .DESCRIPTION
    Since queries run in the background (issue #40) a failure can arrive for a tab the user is not
    looking at. Showing it immediately puts a modal dialog in front of whatever they are doing on a
    different tab, about a query they cannot see - and, because the dialog is modal, it stops them
    working on the tab they ARE looking at until they dismiss something irrelevant to it.

    So a tab-scoped message raised while its tab is off screen is held here and shown when the user
    next opens that tab. Nothing is lost: it is already in the log by the time this is called, and the
    interruption now happens in the context where it makes sense.

    Only WARNING and ERROR reach this - they are the only levels that raise a dialog at all.

    Application-wide failures do NOT come through here. Those are not about a tab and must be seen
    wherever the user is; see the -TabScoped switch on Write-LogOutput for where that line is drawn.

    .PARAMETER TabSession
    The tab the message belongs to.

    .PARAMETER Text
    The message body, already formatted for the dialog.

    .PARAMETER Title
    The dialog title, already carrying the tab name.

    .PARAMETER Icon
    The MessageBoxIcon the dialog would have used.
    #>
    [CmdLetBinding()]
    param(
        $TabSession,
        [string]$Text,
        [string]$Title,
        $Icon
    )

    try {
        if ($null -eq $TabSession) {
            return
        }

        if ($null -eq $TabSession.PendingMessages) {
            $TabSession.PendingMessages = [System.Collections.Generic.List[object]]::new()
        }

        # Capped. A tab whose query fails repeatedly - a stale session retrying, say - must not build
        # an unbounded backlog that then has to be read through when the tab is opened. The oldest go
        # first: the most recent failure is the one that describes the current state.
        while ($TabSession.PendingMessages.Count -ge 10) {
            $TabSession.PendingMessages.RemoveAt(0)
        }

        $TabSession.PendingMessages.Add(@{
                Text  = $Text
                Title = $Title
                Icon  = $Icon
            })
    }
    catch {
        # This is the path that reports failures; it has nowhere useful to report its own.
    }
}

function Show-TabScopedMessage {
    <#
    .SYNOPSIS
    Show whatever was held for a tab while it was off screen, as one dialog.

    .DESCRIPTION
    Called when a tab becomes the visible one. Coalesced into a single dialog on purpose: opening a
    tab that failed four times should not mean dismissing four modals in a row.

    The queue is cleared BEFORE the dialog is shown. A modal pumps the dispatcher, which lets the
    completion poll timer run, which can enqueue another message for this same tab - and if the queue
    were cleared afterwards that message would be discarded unseen.

    .PARAMETER TabSession
    The tab being opened. Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.PendingMessages -or $Private:Target.PendingMessages.Count -eq 0) {
            return
        }

        $Private:Held = @($Private:Target.PendingMessages)
        $Private:Target.PendingMessages.Clear()

        $Private:Title = $Private:Held[-1].Title
        $Private:Icon = $Private:Held[-1].Icon
        $Private:Text = ($Private:Held | ForEach-Object { $_.Text }) -join "`r`n`r`n"

        if ($Private:Held.Count -gt 1) {
            $Private:Text = "{0} messages occurred on this tab while it was not open:`r`n`r`n{1}" -f $Private:Held.Count, $Private:Text
        }

        Show-LogMessageDialog -Text $Private:Text -Title $Private:Title -Icon $Private:Icon
    }
    catch {
        "Could not show the messages held for this tab: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
