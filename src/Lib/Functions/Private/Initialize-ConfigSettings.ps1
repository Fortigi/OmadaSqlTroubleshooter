function Initialize-ConfigSettings {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        Set-ConfigProperty -Reset:$Reset.IsPresent

        if ($Reset.IsPresent -or $NoReconnect.IsPresent -or [string]::IsNullOrWhiteSpace($Script:AppConfig.BaseUrl)) {
            $Script:RunTimeConfig.ReconnectStatus = 1
        }
        else {
            # 0 = Not set
            # 1 = Skip reconnect
            # 2 = Reconnect
            # 3 = Always connect

            if ($null -ne $Script:AppConfig.LastAuthentication -and
                (
                    $Script:AppConfig.LastAuthentication -eq "OAuth" -and
                    $null -ne $Script:AppConfig.UserName -and
                    $null -ne $Script:AppConfig.Password -and
                    $null -ne $Script:AppConfig.EntraApplicationIdUri -and
                    $null -ne $Script:AppConfig.EntraIdTenantId
                ) -or
                (
                    $Script:AppConfig.LastAuthentication -in ("WebView2", "Browser")
                )
            ) {
                $Script:RunTimeConfig.ReconnectStatus = Open-ChoiceForm -Title "Reconnect?" -Message ("Reconnect to '{0}' using existing connection settings?" -f $Script:AppConfig.BaseUrl) -LeftButtonReturnValue 2 -RightButtonReturnValue 1
            }
        }
        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip reconnect" | Write-LogOutput -LogType DEBUG
            Set-SqlConnectionState -Status $false
        }

        if ($Script:RunTimeConfig.Logging.LogToConsole -or $Script:AppConfig.CheckboxConsoleLog) {
            $Script:RunTimeConfig.Logging.LogToConsole = $true
            "Console logging is enabled" | Write-LogOutput -LogType LOG
        }

        if ($null -eq ($Script:MainForm.Definition | Get-FormPositionConfig)) {
            $Script:MainForm.Definition.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        }

        "Pre-set Main Form Components from config" | Write-LogOutput -LogType DEBUG
        $Script:CurrentUrl = $null
        $Script:MainForm.Elements.TextBoxURL.Text = $Script:AppConfig.BaseUrl
        $Script:MainForm.Elements.TextBoxURL.IsEnabled = $true
        if (![String]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxURL.Text)) {
            $Script:CurrentUrl = $Script:MainForm.Elements.TextBoxURL.Text
            "Config: Current Url: {0}" -f $Script:CurrentUrl | Write-LogOutput -LogType DEBUG
        }

        if ($Script:AppConfig.MyCreatedQueriesOnly) {
            "Config: MyCreatedQueriesOnly: True" | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.CheckboxMyCreatedQueries.IsChecked = $true
        }
        if ($Script:AppConfig.MyUpdatedQueriesOnly) {
            "Config: MyUpdatedQueriesOnly: True" | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.CheckboxMyUpdatedQueries.IsChecked = $true
        }

        if ($null -ne $Script:RunTimeConfig.Logging.LogLevelSetting) {
            $Script:RunTimeConfig.Logging.LogLevelSetting | Set-ConfigProperty -Property "LogLevel"
            $Script:RunTimeConfig.Logging.LogLevel = $Script:RunTimeConfig.Logging.LogLevelSetting
            "Config: LogLevelSetting: {0}" -f $Script:RunTimeConfig.Logging.LogLevelSetting | Write-LogOutput -LogType DEBUG
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.LastAuthentication)) {
            "Config: LastAuthentication: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedValue = $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.Items | Where-Object { $_.Content -eq $Script:AppConfig.LastAuthentication }
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.UserName)) {
            "Config: UserName: {0}" -f $Script:AppConfig.UserName | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.TextBoxUserName.Text = $Script:AppConfig.UserName
        }

        if ($null -ne $Script:AppConfig.Password) {
            "Config: Use existing password" | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.TextBoxPassword.Password = $Script:AppConfig.Password | Get-SecureStringFromText
        }

        if ($Script:AppConfig.SavePassword) {
            "Config: CheckboxSavePassword: True" | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.CheckboxSavePassword.IsChecked = $true
        }

        if ($null -ne $Script:AppConfig.UserName -and $null -ne $Script:AppConfig.Password) {
            "Create/Update credential with username {0}" -f $Script:MainForm.Elements.TextBoxUserName.Text | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Credential = [System.Management.Automation.PSCredential]::new($Script:AppConfig.UserName, ($Script:AppConfig.Password | ConvertTo-SecureString))
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.EntraApplicationIdUri)) {
            "Config: EntraApplicationIdUri: {0}" -f $Script:AppConfig.EntraApplicationIdUri | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.TextBoxAppIdUri.Text = $Script:AppConfig.EntraApplicationIdUri
            $Script:RunTimeData.RestMethodParam.EntraApplicationIdUri = $Script:AppConfig.EntraApplicationIdUri
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.EntraIdTenantId)) {
            "Config: EntraIdTenantId: {0}" -f $Script:AppConfig.EntraIdTenantId | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.TextBoxEntraIdTenantId.Text = $Script:AppConfig.EntraIdTenantId
            $Script:RunTimeData.RestMethodParam.EntraIdTenantId = $Script:AppConfig.EntraIdTenantId
        }

        $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
        Set-AuthenticationOption
        Set-OmadaUrl

        if ($Script:RunTimeConfig.ReconnectStatus -ge 2 -and (Test-OmadaConnection)) {
            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Config: CurrentSqlQuery.DoId: {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput -LogType DEBUG

                $ComboBoxSelectQueryItem = $null
                $ComboBoxSelectQueryItem = $Script:MainForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" }
                if ($null -eq $ComboBoxSelectQueryItem) {
                    "Config: Set CurrentSqlQuery.DoId: {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput -LogType DEBUG
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                    $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                    $Script:RunTimeData.CurrentSqlQuery.DisplayName = $Script:AppConfig.CurrentSqlQuery.DisplayName
                    $Script:MainForm.Elements.TextBoxDisplayName.Text = $Script:RunTimeData.CurrentSqlQuery.DisplayName
                }
                $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedValue = $ComboBoxSelectQueryItem
            }

            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.FullName)) {
                "Config: CurrentDataConnection: {0}" -f $Script:AppConfig.CurrentDataConnection.FullName | Write-LogOutput -LogType DEBUG
                Set-DataConnection
            }
            Test-ConnectionSettings
            Test-ConnectionButton
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
