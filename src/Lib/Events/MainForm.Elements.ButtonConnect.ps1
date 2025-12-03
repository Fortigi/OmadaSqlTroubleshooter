$Script:MainForm.Elements.ButtonConnect.Add_Click({
        try {
            $_ | Show-EventInfo

            if ($Script:MainForm.Elements.ButtonConnectText.Text -eq "_Connect") {
                $Script:RunTimeConfig.ReconnectStatus = 2
                if (Test-OmadaConnection) {
                    Test-ConnectionSettings
                }
                if ($Script:ConnectionStatus) {
                    Update-QueryList -ForceRefresh
                    Update-DataConnectionList
                }
            }
            else {
                Set-SqlConnectionState -Status $false
            }
        }
        catch {
            Restore-MainFormFocus
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#$Script:MainForm.Elements.ButtonConnectText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonConnect"
#    })

#$Script:MainForm.Elements.ButtonConnectImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonConnect"
#    })
