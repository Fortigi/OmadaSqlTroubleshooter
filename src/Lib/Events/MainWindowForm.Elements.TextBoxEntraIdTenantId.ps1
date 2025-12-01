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

