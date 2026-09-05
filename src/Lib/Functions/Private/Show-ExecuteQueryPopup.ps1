function Show-ExecuteQueryPopup {
    <#
    .SYNOPSIS
    Show the "Executing Query..." popup for the tab that started the query.

    .DESCRIPTION
    The popup used to live in a single module-scope slot, $Script:PopupWindowExecuteQuery, and that
    one fact produced both of the symptoms reported against it.

    Unlike $Script:MainForm.Elements, $Script:RunTimeData and $Script:AppConfig, that slot was NOT
    repointed by Set-ActiveTabContext, so it was shared by every tab. The window is owned by the main
    form, so it floated above the application no matter which tab was on screen - a tab that was not
    running anything still showed "Executing Query...". And because a second execute overwrote the
    slot, the first tab's window was orphaned: nothing held a reference to it any more, so nothing
    could ever close it, and it stayed on screen until the application exited.

    The popup now belongs to its tab session, like the pending request that owns it, and visibility is
    driven by which tab is actually on screen.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Private:TabSession = Get-ActiveTabSession
        if ($null -eq $Private:TabSession) {
            return
        }

        # A popup already up for this tab is reused rather than replaced. Replacing it is exactly what
        # orphaned windows before.
        if ($null -ne $Private:TabSession.ExecutePopup) {
            Sync-ExecuteQueryPopupVisibility
            return
        }

        $Private:TabSession.ExecutePopup = Show-PopupWindow -Message "Executing Query..."
        Sync-ExecuteQueryPopupVisibility
    }
    catch {
        # Cosmetic. A popup that cannot be shown must never stop a query from running.
        "Could not show the executing-query popup: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Close-ExecuteQueryPopup {
    <#
    .SYNOPSIS
    Close the "Executing Query..." popup belonging to the active tab.

    .DESCRIPTION
    Called from Reset-ExecuteQueryUiState, which always runs with the owning tab made active - the
    completion poll timer steps into the tab before invoking a completion - so "the active tab" is
    the right tab here.

    .PARAMETER TabSession
    The tab whose popup to close. Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.ExecutePopup) {
            return
        }

        try {
            $Private:Target.ExecutePopup.Close()
        }
        catch {
            # Already closed, or the window is gone with the application shutting down.
        }

        $Private:Target.ExecutePopup = $null
    }
    catch {
        "Could not close the executing-query popup: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Sync-ExecuteQueryPopupVisibility {
    <#
    .SYNOPSIS
    Show the popup of the tab currently on screen and hide every other tab's.

    .DESCRIPTION
    Keyed off the tab control's own SelectedItem rather than $Script:ActiveTabId, and that is
    deliberate. $Script:ActiveTabId moves twice for every completion - the poll timer steps into the
    owning tab and restores afterwards - so driving visibility from it would flicker the popup on and
    off against tabs the user is not even looking at. The tab control's selection only changes when
    the user actually switches tabs, which is precisely the question being asked here.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Private:Selected = (Get-TabControlSessions).SelectedItem

        foreach ($Private:Tab in @($Script:Tabs)) {
            if ($null -eq $Private:Tab -or $null -eq $Private:Tab.ExecutePopup) {
                continue
            }

            try {
                if ($null -ne $Private:Selected -and $Private:Tab.TabItem -eq $Private:Selected) {
                    $Private:Tab.ExecutePopup.Show()
                }
                else {
                    $Private:Tab.ExecutePopup.Hide()
                }
            }
            catch {
                # One window that will not co-operate must not stop the others being corrected.
                continue
            }
        }
    }
    catch {
        "Could not synchronise executing-query popups: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
