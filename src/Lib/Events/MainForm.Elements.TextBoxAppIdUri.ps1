$Script:MainFormForm.Elements.TextBoxAppIdUri.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxAppIdUri.Text)) {

                "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
                if ($Script:RunTimeData.RestMethodParam.ContainsKey("EntraApplicationIdUri")) {
                    if (![string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxAppIdUri.Text)) {
                        "Set App Id Uri: {0}" -f $Script:MainFormForm.Elements.TextBoxAppIdUri.Text | Write-LogOutput -LogType DEBUG
                        $Script:MainFormForm.Elements.TextBoxAppIdUri.Text | Set-ConfigProperty -Property "EntraApplicationIdUri"
                        $Script:RunTimeData.RestMethodParam.EntraApplicationIdUri = $Script:MainFormForm.Elements.TextBoxAppIdUri.Text
                    }
                }
                "App Id Uri set" | Write-LogOutput -LogType VERBOSE
                Test-ConnectionButton
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainFormForm.Elements.TextBoxAppIdUri.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArgs
        )
        try {

            $_ | Show-EventInfo

            if ($EventArgs.Key -in ([System.Windows.Input.Key]::Enter, [System.Windows.Input.Key]::Return)) {
                "Enter/Return key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                if ($Script:MainFormForm.Elements.TextBoxUrl.IsEnabled -and $Script:MainFormForm.Elements.TextBoxUrl.Text -like "http*") {
                    "Triggering connect" | Write-LogOutput -LogType VERBOSE
                    Test-ConnectionButton
                    if ($Script:MainFormForm.Elements.ButtonConnect.IsEnabled) {
                        "Executing connection" | Write-LogOutput -LogType VERBOSE
                        $Script:MainFormForm.Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
