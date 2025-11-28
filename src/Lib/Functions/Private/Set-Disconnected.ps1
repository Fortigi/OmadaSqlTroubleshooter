function Set-Disconnected {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $true
        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $false
        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $null
        $Script:MainWindowForm.Elements.CheckboxMyCreatedQueries.IsEnabled = $false
        $Script:MainWindowForm.Elements.CheckboxMyUpdatedQueries.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonNewQuery.IsEnabled = $false
        $Script:MainWindowForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Disconnected"
        $Script:MainWindowForm.Elements.TextBlockStatusBarDatabaseName | Set-TextBlockText -Text "-"
        $Script:MainWindowForm.Elements.TextBlockStatusBarUrl | Set-TextBlockText -Text "-"
        $Script:MainWindowForm.Elements.TextBlockStatusBarQueryTime | Set-TextBlockText -Text "00:00:00.0000000"
        $Script:MainWindowForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "0 rows"
        $Script:MainWindowForm.Elements.DataGridQueryResult.ItemsSource = $null
        $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $false
        $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $null
        $Script:MainWindowForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Clear()
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonOpenOutputFile.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $false

        $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.IsEnabled = $true
        $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $true
        $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $true
        $Script:MainWindowForm.Elements.CheckBoxSavePassword.IsEnabled = $true
        $Script:MainWindowForm.Elements.TextBoxAppIdUri.IsEnabled = $true
        $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $true
        $Script:MainWindowForm.Elements.TextBoxUrl.IsEnabled = $true

        $Script:MainWindowForm.Definition.Title = $Script:RunTimeConfig.ApplicationTitle

        $ScriptToExecute = "editor.setValue('');"
        Push-ToEditor -ScriptToExecute $ScriptToExecute

        $Script:ConnectionStatus = $false
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
