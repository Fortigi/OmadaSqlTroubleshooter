function Complete-TabClose {
    <#
    .SYNOPSIS
    Tears down a tab whose close was requested: disposes its WebView2, removes it from the
    TabControl and $Script:Tabs, and selects a surviving tab. Closing the last tab leaves only the
    "+" add tab (no tab is auto-opened).

    .DESCRIPTION
    Extracted from Close-TabSession so it can be invoked two ways without a closure: directly (no
    unsaved changes / Discard) or deferred via the top-level WebViewCompletionPollTimer once an
    in-flight save Task completes. It is a real named function precisely so both paths resolve this
    module's private functions - a .GetNewClosure() block would run in a detached dynamic module
    that cannot see them, throwing CommandNotFoundException.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabToClose,
        [bool]$WasActiveTab,
        $PreviouslyActiveTab
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $ClosingIndex = $Script:Tabs.IndexOf($TabToClose)

        if ($null -ne $TabToClose.WebView.Object) {
            try {
                $TabToClose.WebView.Object.Dispose()
            }
            catch {
                "Failed to dispose WebView2 for tab '{0}': {1}" -f $TabToClose.DisplayName, $_.Exception.Message | Write-LogOutput -LogType WARNING
            }
        }

        # TabControlSessions must always be resolved via Get-TabControlSessions, not
        # $Script:MainForm.Elements - the latter was just repointed to $TabToClose's own elements.
        $TabControlSessions = Get-TabControlSessions
        $RemainingTabs = @($Script:Tabs | Where-Object { $_.Id -ne $TabToClose.Id })

        # Move the selection to a surviving tab (or to nothing, when this is the last tab) BEFORE
        # removing the closing tab. Removing the currently-selected TabItem would otherwise make
        # WPF auto-select the adjacent "+" tab, whose SelectionChanged handler opens a brand-new
        # tab - the bug where closing a tab spuriously re-opened a query. SuppressAddNewTab is a
        # belt-and-suspenders guard for that same handler during this whole operation.
        $Script:SuppressAddNewTab = $true
        try {
            if ($RemainingTabs.Count -eq 0) {
                # Last tab closed: leave only the "+" add tab, nothing selected/active.
                $TabControlSessions.SelectedItem = $null
            }
            elseif ($WasActiveTab) {
                $NextIndex = [Math]::Min($ClosingIndex, $RemainingTabs.Count - 1)
                $TabControlSessions.SelectedItem = $RemainingTabs[$NextIndex].TabItem
            }

            $TabControlSessions.Items.Remove($TabToClose.TabItem)
            [void]$Script:Tabs.Remove($TabToClose)

            if ($RemainingTabs.Count -eq 0) {
                # Removing the last tab makes WPF auto-select the "+" tab; force it back to no
                # selection so a later click on "+" still registers a selection change and opens a
                # new tab (a click on an already-selected "+" would be a no-op).
                $TabControlSessions.SelectedIndex = -1
                # No active tab remains - clear the active id so nothing treats the just-closed tab
                # as still active.
                $Script:ActiveTabId = $null
                # Disposing every tab's WebView2 tears down the shared CoreWebView2 environment, so
                # the next tab's EnsureCoreWebView2Async would fail against the now-stale one. No tab
                # is left using it, so drop the reference - Initialize-WebViewForTab creates a fresh
                # environment for the next tab.
                $Script:SharedWebViewEnvironment = $null
            }
            elseif (-not $WasActiveTab -and $null -ne $PreviouslyActiveTab) {
                # The on-screen tab is untouched by closing a background tab; just re-sync the
                # globals Set-ActiveTabContext repointed onto $TabToClose earlier.
                Set-ActiveTabContext -TabSession $PreviouslyActiveTab
            }
        }
        finally {
            $Script:SuppressAddNewTab = $false
        }

        # When the active tab was closed and a survivor took over, move keyboard focus onto that
        # survivor. Closing from the editor (Ctrl+W / Ctrl+F4) disposes the closing tab's WebView2
        # while it still held OS keyboard focus, so without this every following shortcut would reach
        # no handler. Closing a background tab leaves the on-screen tab (and its focus) untouched.
        if ($WasActiveTab -and $Script:Tabs.Count -gt 0 -and $null -ne $Script:ActiveTabId) {
            Set-ActiveTabEditorFocus
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
