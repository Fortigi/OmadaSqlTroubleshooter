function Set-ActiveTabEditorFocus {
    <#
    .SYNOPSIS
    Moves keyboard focus into the active tab's Monaco editor (or onto its TabItem when the editor is
    not ready yet), deferred to Background priority so it runs after any pending tab switch has been
    laid out.

    .DESCRIPTION
    The Monaco editor is a WebView2 - a Win32 HwndHost. When a keyboard shortcut changes the active
    tab (Ctrl+Tab switch, Ctrl+Shift+K / Ctrl+T duplicate, Ctrl+W / Ctrl+F4 close) while the editor
    has focus, the OS keyboard focus otherwise stays on the now-hidden (or, for close, disposed)
    WebView2, which stops raising key events - so every following shortcut reaches no handler and the
    application appears to freeze on keystrokes. Calling this after such a tab change puts focus back
    on a live, visible element so the shortcuts keep working. It does not touch the editor's own
    shortcuts (F5 / Ctrl+S handled inside Monaco) - if anything it helps them by focusing the editor.

    The deferred scriptblock captures no locals (it re-derives the active tab) so it stays a plain
    scriptblock that can resolve this module's private functions.
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Dispatcher = $Script:MainForm.Definition.Dispatcher
        if ($null -eq $Dispatcher) {
            return
        }

        $Dispatcher.BeginInvoke(
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
                        "Moved keyboard focus to the editor of tab '{0}'." -f $ActiveTab.DisplayName | Write-LogOutput -LogType DEBUG
                    }
                    elseif ($null -ne $ActiveTab.TabItem) {
                        # No editor yet (e.g. a freshly created tab whose WebView2 is still starting):
                        # focus the TabItem so the window-level PreviewKeyDown keeps catching shortcuts.
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
