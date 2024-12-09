$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Add_DropDownOpened({
        $_ | Show-EventInfo
        try {
            if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 0) {
                Update-DataConnectionList
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })


$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Add_SelectionChanged({
        $_ | Show-EventInfo

        try {
            if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 0) {
                Update-DataConnectionList
            }
            if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content)) {
                $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content | Invoke-ConfigSetting -Property "CurrentDataConnection"

                if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content) -and $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -ne " - ") {
                    $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content | Invoke-ConfigSetting -Property "CurrentDataConnection"
                    $Script:MainWindowForm.Elements.TextBlockDatabaseName.Text = $Script:AppConfig.CurrentDataConnection.DisplayName

                    if (Test-SqlSchemaWindowOpen) {
                        Get-SqlSchemaObject
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })

