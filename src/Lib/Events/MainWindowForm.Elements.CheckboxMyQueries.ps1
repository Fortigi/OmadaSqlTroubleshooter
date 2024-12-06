$Script:MainWindowForm.Elements.CheckboxMyQueries.Add_Checked({
        $_ | Show-EventInfo

        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        $True | Invoke-ProcessConfigSettings -Property "MyQueriesOnly"

        $QueryUrl = "{0}/actusersettingsdlg.aspx?HIDEBACKARRICON=1" -f $Script:AppConfig.BaseUrl
        $Body = $null
        $Method = "GET"
        $Result = Invoke-OmadaPSWebRequestWrapper

        if ($Result -match [regex]("identityUserName:.\S+")) {
            $Match = $Matches[0]
            $IdentityUserName = $Match.Split(":")[1].Trim().TrimStart("'").TrimEnd(",").TrimEnd("'")
            if (![string]::IsNullOrWhiteSpace($IdentityUserName)) {
                $IdentityUserName | Invoke-ProcessConfigSettings -Property "IdentityUserName"
            }
        }
        else {
            $null | Invoke-ProcessConfigSettings -Property "IdentityUserName"
        }
        "Force update query list" | Write-LogOutput -LogType DEBUG
        Update-QueryList -ForceRefresh
    })

$Script:MainWindowForm.Elements.CheckboxMyQueries.Add_Unchecked({
        $_ | Show-EventInfo
        $False | Invoke-ProcessConfigSettings -Property "MyQueriesOnly"
        $null | Invoke-ProcessConfigSettings -Property "IdentityUserName"
        "Force update query list" | Write-LogOutput -LogType DEBUG
        Update-QueryList -ForceRefresh
    })
