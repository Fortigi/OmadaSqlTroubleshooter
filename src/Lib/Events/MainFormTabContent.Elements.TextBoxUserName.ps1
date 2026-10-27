$Script:MainForm.Elements.TextBoxUserName.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text)) {
                $Script:MainForm.Elements.TextBoxUserName.Text | Set-ConfigProperty -Property "UserName"
                "Username set to: {0}" -f $Script:AppConfig.UserName | Write-LogOutput -LogType DEBUG
            }
            elseif ($Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -ne "OAuth") {
                "Username is empty, so no account is preselected for the sign-in" | Write-LogOutput -LogType VERBOSE
            }
            else {
                "Username cannot be empty!" | Write-LogOutput -LogType VERBOSE
            }

            $null = Update-TabCredential
            Test-ConnectionButton
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }

    })

$Script:MainForm.Elements.TextBoxUserName.Add_PreviewKeyDown({
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
