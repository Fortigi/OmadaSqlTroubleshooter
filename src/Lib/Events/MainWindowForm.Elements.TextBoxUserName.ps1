$Script:MainWindowForm.Elements.TextBoxUserName.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text)) {

                $Script:MainWindowForm.Elements.TextBoxUserName.Text | Set-ConfigProperty -Property "UserName"
                "Username set to: {0}" -f $Script:AppConfig.UserName | Write-LogOutput -LogType DEBUG
                #if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text) -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password)) {
                    "Create/Update credential with username {0}" -f $Script:MainWindowForm.Elements.TextBoxUserName.Text | Write-LogOutput -LogType DEBUG
                    $Script:MainWindowForm.Elements.TextBoxUserName.Text | Set-ConfigProperty -Property "UserName"
                    if (!$Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                        $Script:RunTimeData.RestMethodParam.Add("Credential", $null)
                    }
                    $Script:RunTimeData.RestMethodParam.Credential = [System.Management.Automation.PSCredential]::new($Script:AppConfig.UserName, ($Script:MainWindowForm.Elements.TextBoxPassword.Password | ConvertTo-SecureString -AsPlainText -Force))
                }
                #}
                "Username set!" | Write-LogOutput
                Test-ConnectionButton
            }
            if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text)) {
                if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                    "Clear credential because username is empty" | Write-LogOutput -LogType DEBUG
                    $Script:RunTimeData.RestMethodParam.Credential = $null
                    if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -ne "OAuth") {
                        $Script:RunTimeData.RestMethodParam.Remove("Credential")
                    }
                }
                if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -ne "OAuth") {
                    "Username cannot be empty!" | Write-LogOutput -LogType VERBOSE
                }
                else {
                    "Username is empty, so it is not used for authentication" | Write-LogOutput -LogType VERBOSE
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }

    })

$Script:MainWindowForm.Elements.TextBoxUserName.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArgs
        )
        try {

            $_ | Show-EventInfo

            if ($EventArgs.Key -in ([System.Windows.Input.Key]::Enter, [System.Windows.Input.Key]::Return)) {
                "Enter/Return key intercepted at MainWindow level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                if ($Script:MainWindowForm.Elements.TextBoxUrl.IsEnabled -and $Script:MainWindowForm.Elements.TextBoxUrl.Text -like "http*") {
                    "Triggering connect" | Write-LogOutput -LogType VERBOSE
                    Test-ConnectionButton
                    if ($Script:MainWindowForm.Elements.ButtonConnect.IsEnabled) {
                        "Executing connection" | Write-LogOutput -LogType VERBOSE
                        $Script:MainWindowForm.Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
