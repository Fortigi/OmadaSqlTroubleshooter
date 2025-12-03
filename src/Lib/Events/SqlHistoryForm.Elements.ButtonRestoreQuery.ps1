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

            $Result = [System.Windows.MessageBox]::Show(
                "Are you sure you want to restore this query version?`n`nChanged by: $($SelectedItem.ChangedBy)`nChange date: $($SelectedItem.ChangeDate.ToString('yyyy-MM-dd HH:mm:ss'))",
                "Confirm Query Restore",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )

            if ($Result -eq [System.Windows.MessageBoxResult]::Yes) {
                try {

                    if ($null -ne $Script:Webview.Object.CoreWebView2) {

                        $ScriptToExecute = "editor.setValue('{0}');" -f ($SelectedItem.OldValue -replace "`n", "\n" -replace "`r", "\r" -replace "`t", "\t" -replace "'", "\'")
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
