$Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Text)) {

                "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
                if ($Script:RunTimeData.RestMethodParam.ContainsKey("EntraIdTenantId")) {
                    if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Text)) {
                        "Set App Id Uri: {0}" -f $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Text | Write-LogOutput -LogType DEBUG
                        $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Text | Set-ConfigProperty -Property "EntraIdTenantId"
                        $Script:RunTimeData.RestMethodParam.EntraIdTenantId = $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Text
                    }
                }
                "Tenant Id set" | Write-LogOutput -LogType VERBOSE
                Test-ConnectionButton
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Add_PreviewKeyDown({
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

