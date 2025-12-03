$Script:MainForm.Elements.TextBoxPassword.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text)) {

                "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
                #if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text) -and ![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password)) {
                    "Create/Update credential with username {0}" -f $Script:MainForm.Elements.TextBoxUserName.Text | Write-LogOutput -LogType DEBUG
                    $Script:MainForm.Elements.TextBoxUserName.Text | Set-ConfigProperty -Property "UserName"
                    if ($Script:RunTimeConfig.SavePassword) {
                        $Script:MainForm.Elements.TextBoxPassword.Password | Set-ConfigProperty -Property "Password"
                    }
                    else {
                        $null | Set-ConfigProperty -Property "Password"
                    }

                    if (!$Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                        $Script:RunTimeData.RestMethodParam.Add("Credential", $null)
                    }
                    $Script:RunTimeData.RestMethodParam.Credential = [System.Management.Automation.PSCredential]::new($Script:AppConfig.UserName, ($Script:MainForm.Elements.TextBoxPassword.Password | ConvertTo-SecureString -AsPlainText -Force))
                }
                #}
                "Password set" | Write-LogOutput -LogType VERBOSE
                Test-ConnectionButton
            }
            if ([string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password)) {
                if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                    "Clear credential because password is empty" | Write-LogOutput -LogType DEBUG
                    $Script:RunTimeData.RestMethodParam.Credential = $null
                    if ($Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -ne "OAuth") {
                        $Script:RunTimeData.RestMethodParam.Remove("Credential")
                    }
                }
                if ($Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -ne "OAuth") {
                    "Password cannot be empty!" | Write-LogOutput -LogType VERBOSE
                }
                else {
                    "Password is empty, so it is not used for authentication" | Write-LogOutput -LogType VERBOSE
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.TextBoxPassword.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArgs
        )
        try {

            $_ | Show-EventInfo

            if ($EventArgs.Key -in ([System.Windows.Input.Key]::Enter, [System.Windows.Input.Key]::Return)) {
                "Enter/Return key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                if ($Script:MainForm.Elements.TextBoxUrl.IsEnabled -and $Script:MainForm.Elements.TextBoxUrl.Text -like "http*") {
                    "Triggering connect" | Write-LogOutput -LogType VERBOSE
                    Test-ConnectionButton
                    if ($Script:MainForm.Elements.ButtonConnect.IsEnabled) {
                        "Executing connection" | Write-LogOutput -LogType VERBOSE
                        $Script:MainForm.Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
