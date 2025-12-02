$Script:MainWindowForm.Elements.ButtonNewQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $false

            if (!(Test-ConnectionRequirements)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
                Set-SqlConnectionState -Status $false
            }
            else {

                if ($Script:MainWindowForm.Elements.ButtonNewQuery.Text -eq "Delete") {
                    "Delete query query" | Write-LogOutput
                }
                else {

                    "Save query new query" | Write-LogOutput

                    Invoke-SaveEditorValue -NewQuery
                }
            }
        }
        catch {
            Set-SqlConnectionState -Status $false
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
