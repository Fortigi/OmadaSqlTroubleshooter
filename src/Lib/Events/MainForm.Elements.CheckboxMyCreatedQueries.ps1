$Script:MainFormForm.Elements.CheckboxMyCreatedQueries.Add_Checked({
        try {
            $_ | Show-EventInfo


            if (!(Test-ConnectionRequirements)) {
                "Connection not ready" | Write-LogOutput -LogType DEBUG
                return
            }

            $true | Set-ConfigProperty -Property "MyCreatedQueriesOnly"
            if ($Script:ConnectionStatus) {
                $Script:RunTimeData.RestMethodParam.Uri = "{0}/actusersettingsdlg.aspx?HIDEBACKARRICON=1" -f $Script:AppConfig.BaseUrl
                $Script:RunTimeData.RestMethodParam.Body = $null
                $Script:RunTimeData.RestMethodParam.Method = "GET"
                $Result = Invoke-OmadaPSWebRequestWrapper

                if ($Result -match [regex]("identityUserName:.\S+")) {
                    $Match = $Matches[0]
                    $IdentityUserName = $Match.Split(":")[1].Trim().TrimStart("'").TrimEnd(",").TrimEnd("'")
                    if (![string]::IsNullOrWhiteSpace($IdentityUserName)) {
                        $IdentityUserName | Set-ConfigProperty -Property "IdentityUserName"
                    }
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

$Script:MainFormForm.Elements.CheckboxMyCreatedQueries.Add_Unchecked({
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
