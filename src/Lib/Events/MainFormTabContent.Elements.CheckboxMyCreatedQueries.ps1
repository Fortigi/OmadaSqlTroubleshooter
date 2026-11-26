$Script:MainForm.Elements.CheckboxMyCreatedQueries.Add_Checked({
        try {
            $_ | Show-EventInfo


            if (!(Test-ConnectionRequirements)) {
                "Connection not ready" | Write-LogOutput -LogType DEBUG
                return
            }

            $true | Set-ConfigProperty -Property "MyCreatedQueriesOnly"
            if ($Script:ConnectionStatus) {
                $IdentityUserName = Get-OmadaIdentityUserName
                if ($null -ne $IdentityUserName) {
                    $IdentityUserName | Set-ConfigProperty -Property "IdentityUserName"
                }
                else {
                    if (!$Script:AppConfig.MyUpdatedQueriesOnly) {
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

$Script:MainForm.Elements.CheckboxMyCreatedQueries.Add_Unchecked({
        try {
            $_ | Show-EventInfo
            $false | Set-ConfigProperty -Property "MyCreatedQueriesOnly"
            if (!$Script:AppConfig.MyUpdatedQueriesOnly) {
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
