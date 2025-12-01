function Set-DataConnection {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if (!$Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items?.Content?.Contains($Script:AppConfig.CurrentDataConnection.FullName)) {
            $ComboBoxDataConnectionItem = New-Object System.Windows.Controls.ComboBoxItem
            $ComboBoxDataConnectionItem.Content = $Script:AppConfig.CurrentDataConnection.FullName
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Add($ComboBoxDataConnectionItem) | Out-Null
        }
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedValue = $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Where-Object { $_.Content -eq $Script:AppConfig.CurrentDataConnection.FullName }
        $Script:MainWindowForm.Elements.TextBlockStatusBarDatabaseName.Text = $Script:AppConfig.CurrentDataConnection.DisplayName
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
