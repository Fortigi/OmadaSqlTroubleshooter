$Script:MainWindowForm.Elements.TextBoxPassword.Add_LostFocus({
    $_ | Show-EventInfo
    if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text)) {

        "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
        if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
            if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text) -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password)) {
                "Create/Update credential with username {0}" -f $Script:MainWindowForm.Elements.TextBoxUserName.Text | Write-LogOutput -LogType DEBUG
                $Script:MainWindowForm.Elements.TextBoxUserName.Text | Invoke-ConfigSetting -Property "UserName"
                $Script:RunTimeData.RestMethodParam.Credential = [System.Management.Automation.PSCredential]::new($Script:AppConfig.UserName, ($Script:MainWindowForm.Elements.TextBoxPassword.Password | ConvertTo-SecureString -AsPlainText -Force))
            }
        }
        "Password set" | Write-LogOutput
        Test-ConnectionSettings
    }
    if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password)) {
        if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
            "Clear credential because password is empty" | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Credential = $Null
        }
        "Password cannot be empty!" | Write-LogOutput
    }
})

