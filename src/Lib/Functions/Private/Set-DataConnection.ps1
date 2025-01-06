function Set-DataConnection {
    try {


        if (!$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Contains($Script:AppConfig.CurrentDataConnection.FullName)) {
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Add($Script:AppConfig.CurrentDataConnection.FullName) | Out-Null
        }
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedValue = $Script:AppConfig.CurrentDataConnection.FullName
        $Script:MainWindowForm.Elements.TextBlockDatabaseName.Text = $Script:AppConfig.CurrentDataConnection.DisplayName
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
