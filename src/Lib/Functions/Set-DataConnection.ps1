function Set-DataConnection {
    try {
        if (!$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Contains((Get-ConfigMultiValue $Script:AppConfig.CurrentDataConnection))) {
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Add((Get-ConfigMultiValue $Script:AppConfig.CurrentDataConnection)) | Out-Null
            (Get-ConfigMultiValue $Script:AppConfig.CurrentDataConnection -Array)[0] | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionName"
            (Get-ConfigMultiValue $Script:AppConfig.CurrentDataConnection -Array)[1] | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionId"

        }
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedValue = (Get-ConfigMultiValue $Script:AppConfig.CurrentDataConnection)
        $Script:MainWindowForm.Elements.TextBlockDatabaseName.Text = $Script:AppConfig.CurrentDataConnectionName
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
