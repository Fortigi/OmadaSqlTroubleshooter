function Set-DataConnection {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if (!$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items?.Content?.Contains($Script:AppConfig.CurrentDataConnection.FullName)) {
            $ComboBoxDataConnectionItem = New-Object System.Windows.Controls.ComboBoxItem
            $ComboBoxDataConnectionItem.Content = $Script:AppConfig.CurrentDataConnection.FullName
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Add($ComboBoxDataConnectionItem) | Out-Null
        }
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedValue = $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Where-Object { $_.Content -eq $Script:AppConfig.CurrentDataConnection.FullName }
        $Script:MainWindowForm.Elements.TextBlockDatabaseName.Text = $Script:AppConfig.CurrentDataConnection.DisplayName
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
