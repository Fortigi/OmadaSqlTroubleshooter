$Script:MainForm.Elements.CheckboxMyUpdatedQueries.Add_Checked({
        try {
            $_ | Show-EventInfo

            if (!(Test-ConnectionRequirements)) {
                "Connection not ready" | Write-LogOutput -LogType DEBUG
                return
            }

            $true | Set-ConfigProperty -Property "MyUpdatedQueriesOnly"
            if ($Script:ConnectionStatus) {

                $IdentityUserName = Get-OmadaIdentityUserName
                if ($null -ne $IdentityUserName) {
                    $IdentityUserName | Set-ConfigProperty -Property "IdentityUserName"
                }
                else {
                    if (!$Script:AppConfig.MyCreatedQueriesOnly) {
                        $null | Set-ConfigProperty -Property "IdentityUserName"
                    }
                }
                "Force update query list" | Write-LogOutput -LogType DEBUG
                Update-QueryList -ForceRefresh
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.CheckboxMyUpdatedQueries.Add_Unchecked({
        try {
            $_ | Show-EventInfo
            $false | Set-ConfigProperty -Property "MyUpdatedQueriesOnly"
            if (!$Script:AppConfig.MyCreatedQueriesOnly) {
                $null | Set-ConfigProperty -Property "IdentityUserName"
            }
            if ($Script:ConnectionStatus) {
                "Force update query list" | Write-LogOutput -LogType DEBUG
                Update-QueryList -ForceRefresh
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
