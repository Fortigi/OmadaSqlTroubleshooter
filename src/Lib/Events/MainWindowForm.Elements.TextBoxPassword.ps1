$Script:MainWindowForm.Elements.TextBoxPassword.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text)) {

                "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
                #if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text) -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password)) {
                    "Create/Update credential with username {0}" -f $Script:MainWindowForm.Elements.TextBoxUserName.Text | Write-LogOutput -LogType DEBUG
                    $Script:MainWindowForm.Elements.TextBoxUserName.Text | Set-ConfigProperty -Property "UserName"
                    if ($Script:RunTimeConfig.SavePassword) {
                        $Script:MainWindowForm.Elements.TextBoxPassword.Password | Set-ConfigProperty -Property "Password"
                    }
                    else {
                        $null | Set-ConfigProperty -Property "Password"
                    }

                    if (!$Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                        $Script:RunTimeData.RestMethodParam.Add("Credential", $null)
                    }
                    $Script:RunTimeData.RestMethodParam.Credential = [System.Management.Automation.PSCredential]::new($Script:AppConfig.UserName, ($Script:MainWindowForm.Elements.TextBoxPassword.Password | ConvertTo-SecureString -AsPlainText -Force))
                }
                #}
                "Password set" | Write-LogOutput -LogType VERBOSE
                Test-ConnectionButton
            }
            if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password)) {
                if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                    "Clear credential because password is empty" | Write-LogOutput -LogType DEBUG
                    $Script:RunTimeData.RestMethodParam.Credential = $null
                    if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -ne "OAuth") {
                        $Script:RunTimeData.RestMethodParam.Remove("Credential")
                    }
                }
                if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -ne "OAuth") {
                    "Password cannot be empty!" | Write-LogOutput -LogType VERBOSE
                }
                else {
                    "Password is empty, so it is not used for authentication" | Write-LogOutput -LogType VERBOSE
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })

