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
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })

