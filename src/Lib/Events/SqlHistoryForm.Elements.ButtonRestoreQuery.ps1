$Script:SqlHistoryForm.Elements.ButtonRestoreQuery.Add_Click({
        param (
            $Sender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo

            # The version the selection is in: cells as well as rows can be selected.
            $SelectedItem = Get-SqlHistorySelectedItem

            if ($null -eq $SelectedItem) {
                "Select one version (a row, or cells in one row) to restore." | Write-LogOutput -LogType WARNING
                return
            }

            # See Suspend-WebViewCompletionPolling.ps1 - MessageBox.Show() pumps this thread's
            # messages while blocked, which could let the WebView2 completion poll timer fire
            # reentrantly.
            Suspend-WebViewCompletionPolling
            try {
                $Result = [System.Windows.MessageBox]::Show(
                    "Are you sure you want to restore this query version?`n`nChanged by: $($SelectedItem.ChangedBy)`nChange date: $(Format-OmadaHistoryDate -Value $SelectedItem.ChangeDate)",
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

                    # Into the tab that holds this query: the active one for the toolbar's History,
                    # possibly another - or a new - one when the history was opened from the query
                    # manager. See Restore-SqlQueryVersion, which also explains why a restored version
                    # now counts as an unsaved change.
                    Restore-SqlQueryVersion -DoId $SelectedItem.DoId -QueryName $SelectedItem.SqlObjectName -Text $SelectedItem.OldValue
                    "Query restored from history: {0}" -f (Format-OmadaHistoryDate -Value $SelectedItem.ChangeDate) | Write-LogOutput

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
