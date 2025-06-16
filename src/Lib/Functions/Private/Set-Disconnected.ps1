function Set-Disconnected {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $False
        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
        $Script:MainWindowForm.Elements.CheckboxMyCreatedQueries.IsEnabled = $False
        $Script:MainWindowForm.Elements.CheckboxMyUpdatedQueries.IsEnabled = $False
        $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $False
        $Script:MainWindowForm.Elements.ButtonNewQuery.IsEnabled = $False
        $Script:MainWindowForm.Elements.TextBlockConnectionStatus | Set-TextBlockText -Text "Disconnected"
        $Script:MainWindowForm.Elements.TextBlockUrl | Set-TextBlockText -Text "-"
        $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $False
        $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $null
        $Script:MainWindowForm.Elements.ButtonConnect | Set-ButtonContent -Content "_Connect"
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items.Clear()
        $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonOpenOutputFile.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $false


        $Script:ConnectionStatus = $false

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
