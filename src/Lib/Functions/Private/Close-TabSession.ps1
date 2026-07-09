function Close-TabSession {
    <#
    .SYNOPSIS
    Closes a tab. Prompts to save first if the tab has unsaved query changes. Never leaves the
    application with zero tabs - closing the last remaining tab immediately opens a fresh one.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabId
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $TabToClose = $Script:Tabs | Where-Object { $_.Id -eq $TabId }
        if ($null -eq $TabToClose) {
            "Close-TabSession: tab '{0}' not found." -f $TabId | Write-LogOutput -LogType WARNING
            return
        }

        # Operate against the tab being closed, so IsDirty/Save act on its own state
        # regardless of which tab happens to be active right now.
        Set-ActiveTabContext -TabSession $TabToClose

        if ($TabToClose.IsDirty) {
            $Choice = Open-ChoiceForm -Title "Unsaved changes" -Message ("Save changes to '{0}' before closing?" -f $TabToClose.DisplayName) -LeftButtonText "Save" -RightButtonText "Discard" -LeftButtonReturnValue 1 -RightButtonReturnValue 2
            if ($Choice -eq 1) {
                Invoke-SaveEditorValue
            }
        }

        $ClosingIndex = $Script:Tabs.IndexOf($TabToClose)

        if ($null -ne $TabToClose.WebView.Object) {
            try {
                $TabToClose.WebView.Object.Dispose()
            }
            catch {
                "Failed to dispose WebView2 for tab '{0}': {1}" -f $TabToClose.DisplayName, $_.Exception.Message | Write-LogOutput -LogType WARNING
            }
        }

        $Script:MainForm.Elements.TabControlSessions.Items.Remove($TabToClose.TabItem)
        [void]$Script:Tabs.Remove($TabToClose)

        if ($Script:Tabs.Count -eq 0) {
            "Last tab closed; opening a fresh one." | Write-LogOutput -LogType DEBUG
            New-TabSession | Out-Null
            return
        }

        if ($Script:ActiveTabId -eq $TabId) {
            $NextIndex = [Math]::Min($ClosingIndex, $Script:Tabs.Count - 1)
            $Script:MainForm.Elements.TabControlSessions.SelectedItem = $Script:Tabs[$NextIndex].TabItem
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
