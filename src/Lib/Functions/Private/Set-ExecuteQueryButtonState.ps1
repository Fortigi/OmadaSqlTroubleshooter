function Set-ExecuteQueryButtonState {
    <#
    .SYNOPSIS
    Make the Execute button read "Execute" or "Cancel" according to whether the active tab has a
    query in flight.

    .DESCRIPTION
    Issue #40's Cancel. The button the user just pressed becomes the way to stop - the same pattern
    the Connect button already uses for Disconnect (Test-ConnectionButton), so there is no new
    control and no new place for a tab's state to disagree with what is on screen.

    Driven off the completion queue via Get-ActiveExecuteQueryRequest, so it is correct whenever it
    is called and needs no flag kept in step. It is called after dispatch, after completion, and from
    Initialize-UiComponents - which Set-ActiveTabContext runs on every tab switch, so switching to a
    tab that is still executing shows Cancel, and switching away and back does not lose it.

    .NOTES
    Cancel here means "stop waiting", not "stop the query". Omada goes on executing it; there is no
    server-side cancellation to call (that is issue #43). The tooltip says so rather than implying a
    power the app does not have.
    #>
    [CmdLetBinding()]
    param()

    try {
        if ($null -eq $Script:MainForm -or $null -eq $Script:MainForm.Elements -or $null -eq $Script:MainForm.Elements.ButtonExecuteQuery) {
            return
        }

        $Private:InFlight = $null -ne (Get-ActiveExecuteQueryRequest)

        if ($Private:InFlight) {
            # Enabled, deliberately: this is the one control that must stay live while the rest of
            # the query controls are disabled, because it is now the way out.
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
            $Script:MainForm.Elements.ButtonExecuteQuery.ToolTip = "Stop waiting for this query. The query itself keeps running on the server."
            if ($null -ne $Script:MainForm.Elements.ButtonExecuteQueryText) {
                $Script:MainForm.Elements.ButtonExecuteQueryText | Set-ButtonText -Value "_Cancel"
            }
            if ($null -ne $Script:MainForm.Elements.ButtonExecuteQueryImage) {
                # Segoe MDL2 "Cancel" (E711), replacing the "Play" glyph.
                $Script:MainForm.Elements.ButtonExecuteQueryImage.Text = [char]0xE711
            }
        }
        else {
            $Script:MainForm.Elements.ButtonExecuteQuery.ToolTip = "Execute"
            if ($null -ne $Script:MainForm.Elements.ButtonExecuteQueryText) {
                $Script:MainForm.Elements.ButtonExecuteQueryText | Set-ButtonText -Value "_Execute"
            }
            if ($null -ne $Script:MainForm.Elements.ButtonExecuteQueryImage) {
                $Script:MainForm.Elements.ButtonExecuteQueryImage.Text = [char]0xE768
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
