(Get-TabControlSessions).Add_SelectionChanged({
        param(
            $EventSender,
            $EventArgs
        )
        try {
            $_ | Show-EventInfo

            $SelectedItem = (Get-TabControlSessions).SelectedItem
            if ($null -eq $SelectedItem) {
                return
            }

            if ($SelectedItem.Name -eq "TabItemAddNew") {
                $MaxCapacity = if ($null -ne $Script:AppGlobalConfig -and $Script:AppGlobalConfig.TabCapacity -gt 0) { $Script:AppGlobalConfig.TabCapacity } else { 8 }
                if (Test-TabCapacity -CurrentCount $Script:Tabs.Count -MaxCapacity $MaxCapacity) {
                    New-TabSession | Out-Null
                }
                else {
                    "Cannot open a new tab: capacity of {0} tabs reached." -f $MaxCapacity | Write-LogOutput -LogType WARNING
                    $CurrentTab = Get-ActiveTabSession
                    if ($null -ne $CurrentTab) {
                        (Get-TabControlSessions).SelectedItem = $CurrentTab.TabItem
                    }
                }
                return
            }

            $TabSession = $Script:Tabs | Where-Object { $_.TabItem -eq $SelectedItem }
            if ($null -ne $TabSession) {
                Set-ActiveTabContext -TabSession $TabSession
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
