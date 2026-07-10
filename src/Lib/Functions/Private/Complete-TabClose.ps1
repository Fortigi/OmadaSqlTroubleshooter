function Complete-TabClose {
    <#
    .SYNOPSIS
    Tears down a tab whose close was requested: disposes its WebView2, removes it from the
    TabControl and $Script:Tabs, and decides which tab becomes active next (never leaving the app
    with zero tabs).

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
        $TabControlSessions.Items.Remove($TabToClose.TabItem)
        [void]$Script:Tabs.Remove($TabToClose)

        if ($Script:Tabs.Count -eq 0) {
            "Last tab closed; opening a fresh one." | Write-LogOutput -LogType DEBUG
            New-TabSession | Out-Null
            return
        }

        if ($WasActiveTab) {
            $NextIndex = [Math]::Min($ClosingIndex, $Script:Tabs.Count - 1)
            $TabControlSessions.SelectedItem = $Script:Tabs[$NextIndex].TabItem
        }
        elseif ($null -ne $PreviouslyActiveTab) {
            # The tab that was actually on screen is untouched by this close - the TabControl's
            # own selection never moved, so just restore the globals Set-ActiveTabContext
            # repointed onto $TabToClose earlier, without disturbing that selection.
            Set-ActiveTabContext -TabSession $PreviouslyActiveTab
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
