$Script:SqlHistoryForm.Elements.ButtonRestoreQuery.Add_Click({
        param (
            $Sender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo

            $SelectedItem = $Script:SqlHistoryForm.Elements.DataGridHistory.SelectedItem

            if ($null -eq $SelectedItem) {
                "No history item selected" | Write-LogOutput -LogType WARNING
                return
            }

            # See Suspend-WebViewCompletionPolling.ps1 - MessageBox.Show() pumps this thread's
            # messages while blocked, which could let the WebView2 completion poll timer fire
            # reentrantly.
            Suspend-WebViewCompletionPolling
            try {
                $Result = [System.Windows.MessageBox]::Show(
                    "Are you sure you want to restore this query version?`n`nChanged by: $($SelectedItem.ChangedBy)`nChange date: $($SelectedItem.ChangeDate.ToString('yyyy-MM-dd HH:mm:ss'))",
                    "Confirm Query Restore",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question
                )
            }
            finally {
                Resume-WebViewCompletionPolling
            }

            if ($Result -eq [System.Windows.MessageBoxResult]::Yes) {
                try {

                    if ($null -ne $Script:Webview.Object.CoreWebView2) {

                        # window.setEditorValue (not editor.setValue directly) so Monaco's
                        # __suppressDirty contract holds - restoring a history version is a
                        # programmatic load, not a genuine user edit, and must not mark the tab dirty.
                        $ScriptToExecute = "window.setEditorValue('{0}');" -f ($SelectedItem.OldValue -replace "`n", "\n" -replace "`r", "\r" -replace "`t", "\t" -replace "'", "\'")
                        Push-ToEditor -ScriptToExecute $ScriptToExecute
                        $Script:RunTimeData.CurrentQueryText = $SelectedItem.OldValue
                        "Query restored to editor!" | Write-LogOutput
                    }
                    "Query restored from history: {0}" -f $SelectedItem.ChangeDate.ToString('yyyy-MM-dd HH:mm:ss') | Write-LogOutput

                    $Script:SqlHistoryForm.Definition.Close()
                }
                catch {
                    "Failed to restore query from history" | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }

    })

#$Script:SqlHistoryForm.Elements.ButtonRestoreQueryText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonRestoreQuery"
#    })

#$Script:SqlHistoryForm.Elements.ButtonRestoreQueryImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonRestoreQuery"
#    })
