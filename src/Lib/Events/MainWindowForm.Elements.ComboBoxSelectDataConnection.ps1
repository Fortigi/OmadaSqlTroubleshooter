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
                (Set-ConfigMultiValue $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content) | Invoke-ProcessConfigSettings -Property "CurrentDataConnection"

                if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content) -and $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -ne " - ") {
                    (Split-NameDoIdString -InputString  $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -JoinString " - ").DoId | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionId"
                    (Split-NameDoIdString -InputString  $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -JoinString " - ").DisplayName | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionName"
                    $Script:MainWindowForm.Elements.TextBlockDatabaseName.Text = (Split-NameDoIdString -InputString  $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content -JoinString " - ").DoId

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

