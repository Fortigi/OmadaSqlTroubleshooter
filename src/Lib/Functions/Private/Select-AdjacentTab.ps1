function Select-AdjacentTab {
    <#
    .SYNOPSIS
    Selects the tab next to the active one, wrapping around: -Direction Next moves right (and from
    the last tab jumps to the first), -Direction Previous moves left (and from the first tab jumps
    to the last). Only the real session tabs are cycled - the "+" add tab is never selected. Drives
    the Ctrl+Tab / Ctrl+Shift+Tab shortcuts.

    .DESCRIPTION
    After switching, keyboard focus is moved into the newly selected tab's editor. This is required
    because the Monaco editor is a WebView2 (a Win32 HwndHost): when the switch is triggered while
    the editor has focus, the OS keyboard focus otherwise stays on the now-hidden WebView2, which
    stops raising key events - so only the first Ctrl+Tab would work and every following press would
    reach nothing. Moving focus onto the visible tab's WebView2 (or its TabItem when it has no
    editor yet) keeps the shortcut working on every press.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Next", "Previous")]
        [string]$Direction
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Count = $Script:Tabs.Count
        if ($Count -le 1) {
            return
        }

        # $Script:Tabs is kept in the same order as the visible tabs (Move-TabSession keeps drag
        # reordering in sync), so its index order is the left-to-right tab order.
        $Active = Get-ActiveTabSession
        $Index = if ($null -ne $Active) { $Script:Tabs.IndexOf($Active) } else { 0 }
        if ($Index -lt 0) {
            $Index = 0
        }

        $NewIndex = if ($Direction -eq "Next") { ($Index + 1) % $Count } else { ($Index - 1 + $Count) % $Count }
        (Get-TabControlSessions).SelectedItem = $Script:Tabs[$NewIndex].TabItem

        # Setting SelectedItem raises SelectionChanged synchronously, so the newly selected tab is
        # already the active tab here. Defer the focus move to Background priority so it runs after
        # the tab content has been made visible/laid out. The scriptblock captures no locals (it
        # re-derives the active tab) so it stays a plain scriptblock that can resolve module state.
        $Script:MainForm.Definition.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [System.Action] {
                try {
                    $ActiveTab = Get-ActiveTabSession
                    if ($null -eq $ActiveTab) {
                        return
                    }

                    $WebViewObject = $ActiveTab.WebView.Object
                    if ($null -ne $WebViewObject) {
                        [void]$WebViewObject.Focus()
                        if ($WebViewObject.IsLoaded -and $null -ne $WebViewObject.CoreWebView2) {
                            $WebViewObject.CoreWebView2.ExecuteScriptAsync("if (window.editor) { editor.focus(); }") | Out-Null
                        }
                        "Moved keyboard focus to the editor of tab '{0}' after tab switch." -f $ActiveTab.DisplayName | Write-LogOutput -LogType DEBUG
                    }
                    elseif ($null -ne $ActiveTab.TabItem) {
                        # No editor yet (e.g. a brand new empty tab): focus the TabItem so the
                        # window-level PreviewKeyDown keeps catching the next Ctrl+Tab.
                        [void]$ActiveTab.TabItem.Focus()
                    }
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType VERBOSE
                }
            }
        ) | Out-Null
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
