$Script:MainForm.Elements.TextBoxPassword.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            # An empty password is allowed: a password is only needed for password based
            # authentication. With only a username, Update-TabCredential creates a credential that
            # names the account and leaves the sign-in to complete passwordless.
            if ([string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password)) {
                "Password is empty" | Write-LogOutput -LogType DEBUG
            }
            else {
                "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
            }

            if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text)) {
                $Script:MainForm.Elements.TextBoxUserName.Text | Set-ConfigProperty -Property "UserName"
            }
            if ($Script:AppConfig.SavePassword -and ![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password)) {
                $Script:MainForm.Elements.TextBoxPassword.Password | Set-ConfigProperty -Property "Password"
            }
            else {
                $null | Set-ConfigProperty -Property "Password"
            }

            $null = Update-TabCredential
            Test-ConnectionButton
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
