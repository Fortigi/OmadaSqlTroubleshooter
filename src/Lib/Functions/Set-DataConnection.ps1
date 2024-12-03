function Set-DataConnection {
    try {
        if (!$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Contains($Script:AppConfig.CurrentDataConnection)) {
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Add($Script:AppConfig.CurrentDataConnection) | Out-Null
            $Script:AppConfig.CurrentDataConnection.Split(" - ")[0].Trim() | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionName"
            $Script:AppConfig.CurrentDataConnection.Split(" - ")[1].Trim() | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionId"

        }
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedValue = $Script:AppConfig.CurrentDataConnection
        $Script:MainWindowForm.Elements.TextBlockDatabaseName.Text = $Script:AppConfig.CurrentDataConnection.Split(" - ")[0].Trim()
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
