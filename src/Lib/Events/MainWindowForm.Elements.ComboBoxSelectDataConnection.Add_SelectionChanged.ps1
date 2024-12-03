$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Add_SelectionChanged({
    $_ | Show-EventInfo

    try {
        if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -ge 0 -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem)) {
            Update-DataConnectionList
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem | Invoke-ProcessConfigSettings -Property "CurrentDataConnection"
        }
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Split(" - ")[0].Trim() | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionName"
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Split(" - ")[1].Trim() | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionId"
        $Script:MainWindowForm.Elements.TextBlockDatabaseName.Text = $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Split(" - ")[0].Trim()

        if (Test-SqlSchemaWindowOpen) {
            Get-SqlSchemaObject
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
})
