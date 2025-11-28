$Script:MainWindowForm.Elements.ButtonConnect.Add_Click({
        try {
            $_ | Show-EventInfo

            if ($Script:MainWindowForm.Elements.ButtonConnectText.Text -eq "_Connect") {
                if (Test-OmadaConnection) {
                    Test-ConnectionSettings
                }
            }
            else {
                Set-Disconnected
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })
