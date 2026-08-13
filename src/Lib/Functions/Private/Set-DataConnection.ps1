function Set-DataConnection {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if (!$Script:MainForm.Elements.ComboBoxSelectDataConnection.Items?.Content?.Contains($Script:AppConfig.CurrentDataConnection.FullName)) {
            $ComboBoxDataConnectionItem = New-Object System.Windows.Controls.ComboBoxItem
            $ComboBoxDataConnectionItem.Content = $Script:AppConfig.CurrentDataConnection.FullName
            $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items.Add($ComboBoxDataConnectionItem) | Out-Null
        }
        # SelectedItem (not SelectedValue) - Update-DataConnectionList (the proven-working path)
        # and Update-TabHeaderTitle both read SelectedItem directly. -First 1 guarantees a single
        # item (WPF SelectedItem must not be assigned a multi-item Where-Object enumeration).
        $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem = $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Where-Object { $_.Content -eq $Script:AppConfig.CurrentDataConnection.FullName } | Select-Object -First 1
        $Script:MainForm.Elements.TextBlockStatusBarDatabaseName.Text = $Script:AppConfig.CurrentDataConnection.DisplayName
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
