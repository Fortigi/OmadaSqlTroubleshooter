$Script:MainWindowForm.Elements.TextBoxAppIdUri.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxAppIdUri.Text)) {

                "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
                if ($Script:RunTimeData.RestMethodParam.ContainsKey("EntraApplicationIdUri")) {
                    if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxAppIdUri.Text)) {
                        "Set App Id Uri: {0}" -f $Script:MainWindowForm.Elements.TextBoxAppIdUri.Text | Write-LogOutput -LogType DEBUG
                        $Script:MainWindowForm.Elements.TextBoxAppIdUri.Text | Set-ConfigProperty -Property "EntraApplicationIdUri"
                        $Script:RunTimeData.RestMethodParam.EntraApplicationIdUri = $Script:MainWindowForm.Elements.TextBoxAppIdUri.Text
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

$Script:MainWindowForm.Elements.TextBoxAppIdUri.Add_PreviewKeyDown({
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
                        $Script:MainWindowForm.Elements.TextBoxUrl.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ModifierKeys]::KeyDownEvent))
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
