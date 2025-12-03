$Script:SqlHistoryForm.Elements.ButtonExportHistory.Add_Click({

        param (
            $Sender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo

            $SaveFileDialog = New-Object Microsoft.Win32.SaveFileDialog
            $SaveFileDialog.Title = "Export SQL History"
            $SaveFileDialog.Filter = "CSV Files (*.csv)|*.csv|JSON Files (*.json)|*.json|Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
            $SaveFileDialog.DefaultExt = ".csv"
            $SaveFileDialog.FileName = "SQL_History_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"

            $Result = $SaveFileDialog.ShowDialog()

            if ($Result -eq $true) {
                $FilePath = $SaveFileDialog.FileName
                $Extension = [System.IO.Path]::GetExtension($FilePath).ToLower()

                $HistoryData = $Script:SqlHistoryForm.Elements.DataGridHistory.ItemsSource

                if ($null -eq $HistoryData -or $HistoryData.Count -eq 0) {
                    "No history data to export" | Write-LogOutput -LogType WARNING
                    return
                }

                switch ($Extension) {
                    ".csv" {
                        $HistoryData | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
                    }
                    ".json" {
                        $HistoryData | ConvertTo-Json -Depth 3 | Set-Content -Path $FilePath -Encoding UTF8
                    }
                    default {

                        $TextContent = @()
                        $TextContent += "SQL Query History Export - Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
                        $TextContent += "=" * 80
                        $TextContent += ""

                        foreach ($Item in $HistoryData) {
                            $TextContent += "Change Date: $($Item.ChangeDate.ToString('yyyy-MM-dd HH:mm:ss'))"
                            $TextContent += "Changed By: $($Item.ChangedBy)"
                            $TextContent += "Change Type: $($Item.ChangeType)"
                            $TextContent += "Object: $($Item.SqlObjectName)"
                            $TextContent += "DoId: $($Item.DoId)"
                            $TextContent += ""
                            $TextContent += "Old Value:"
                            $TextContent += "-" * 40
                            $TextContent += $Item.OldValue
                            $TextContent += ""
                            $TextContent += "New Value:"
                            $TextContent += "-" * 40
                            $TextContent += $Item.NewValue
                            $TextContent += ""
                            $TextContent += "=" * 80
                            $TextContent += ""
                        }

                        $TextContent | Set-Content -Path $FilePath -Encoding UTF8
                    }
                }

                "SQL history exported to: $FilePath" | Write-LogOutput

                $OpenResult = [System.Windows.MessageBox]::Show(
                    "SQL history has been exported successfully.`n`nWould you like to open the exported file?",
                    "Export Complete",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Information
                )

                if ($OpenResult -eq [System.Windows.MessageBoxResult]::Yes) {
                    Start-Process $FilePath
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

##$Script:SqlHistoryForm.Elements.ButtonExportHistoryText.Add_MouseLeftButtonDown({
##        Invoke-ButtonClick -ButtonName "ButtonExportHistory"
##    })

##$Script:SqlHistoryForm.Elements.ButtonExportHistoryImage.Add_MouseLeftButtonDown({
##        Invoke-ButtonClick -ButtonName "ButtonExportHistory"
##    })
