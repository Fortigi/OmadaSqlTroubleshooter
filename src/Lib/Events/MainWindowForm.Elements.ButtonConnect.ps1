$Script:MainWindowForm.Elements.ButtonConnect.Add_Click({
        try {
            $_ | Show-EventInfo
            if($Script:MainWindowForm.Elements.ButtonConnect.Content -eq "_Connect"){
                Test-ConnectionSettings
            }
            else{
                #Reload OmadaWeb.PS to delete cookies (TODO: Add disconnect function to OmadaWeb.PS)
                Import-Module OmadaWeb.PS -Force
                Set-Disconnected
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })
