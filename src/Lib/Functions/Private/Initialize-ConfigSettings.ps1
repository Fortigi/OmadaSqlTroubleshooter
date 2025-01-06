function Initialize-ConfigSettings {
    try {

        Invoke-ConfigSetting -Reset:$Reset.IsPresent

        if ($Script:RunTimeConfig.LogToConsole -or $Script:AppConfig.CheckboxConsoleLog) {
            $Script:RunTimeConfig.LogToConsole = $true
            "Console logging is enabled" | Write-LogOutput -LogType LOG
        }

        if ($null -eq ($Script:MainWindowForm.Definition | Get-WindowPositionConfig)) {
            $Script:MainWindowForm.Definition.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        }

        "Pre-set Main Window Components from config" | Write-LogOutput -LogType DEBUG
        $Script:CurrentUrl = $Null
        $Script:MainWindowForm.Elements.TextBoxURL.Text = $Script:AppConfig.BaseUrl
        $Script:MainWindowForm.Elements.TextBoxURL.IsEnabled = $True
        if (![String]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text)) {
            $Script:CurrentUrl = $Script:MainWindowForm.Elements.TextBoxURL.Text
            "Config: Current Url: {0}" -f $Script:CurrentUrl | Write-LogOutput -LogType DEBUG
        }

        if ($Script:AppConfig.MyQueriesOnly) {
            "Config: MyQueriesOnly: True" | Write-LogOutput -LogType DEBUG
            $Script:MainWindowForm.Elements.CheckboxMyQueries.IsChecked = $True
        }

        if ($null -ne $Script:RunTimeConfig.Logging.LogLevelSetting) {
            $Script:RunTimeConfig.Logging.LogLevelSetting | Invoke-ConfigSetting -Property "LogLevel"
            "Config: LogLevelSetting: {0}" -f $Script:RunTimeConfig.Logging.LogLevelSetting | Write-LogOutput -LogType DEBUG
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
            "Config: CurrentSqlQuery.DoId: {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput -LogType DEBUG

            $ComboBoxSelectQueryItem = $null
            $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq $Script:AppConfig.CurrentSqlQuery.FullName }
            if ($null -eq $ComboBoxSelectQueryItem) {
                "Config: Set CurrentSqlQuery.DoId: {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput -LogType DEBUG
                $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                $Script:RunTimeData.CurrentSqlQuery.DisplayName = $Script:AppConfig.CurrentSqlQuery.DisplayName
                $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $Script:RunTimeData.CurrentSqlQuery.DisplayName
            }
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedValue = $ComboBoxSelectQueryItem
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.FullName)) {
            "Config: CurrentDataConnection: {0}" -f $Script:AppConfig.CurrentDataConnection.FullName | Write-LogOutput -LogType DEBUG
            Set-DataConnection
        }

        if ([string]::IsNullOrWhiteSpace($Script:AppConfig.LastAuthentication)) {
            "Config: LastAuthentication: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedValue = $Script:AppConfig.LastAuthentication
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.UserName)) {
            "Config: UserName: {0}" -f $Script:AppConfig.UserName | Write-LogOutput -LogType DEBUG
            $Script:MainWindowForm.Elements.TextBoxUserName.Text = $Script:AppConfig.UserName
        }
        Set-OmadaUrl
        Set-AuthenticationOption
        Test-ConnectionSettings

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
