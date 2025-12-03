$Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Add_LostFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Text)) {

                "Password set to: {0}" -f "***********" | Write-LogOutput -LogType DEBUG
                if ($Script:RunTimeData.RestMethodParam.ContainsKey("EntraIdTenantId")) {
                    if (![string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Text)) {
                        "Set App Id Uri: {0}" -f $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Text | Write-LogOutput -LogType DEBUG
                        $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Text | Set-ConfigProperty -Property "EntraIdTenantId"
                        $Script:RunTimeData.RestMethodParam.EntraIdTenantId = $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Text
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

$Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Add_PreviewKeyDown({
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

