$Script:MainForm.Elements.ButtonConnect.Add_Click({
        try {
            $_ | Show-EventInfo

            if ($Script:MainForm.Elements.ButtonConnectText.Text -eq "_Connect") {
                $Script:RunTimeConfig.ReconnectStatus = 2

                # OmadaWeb.PS's interactive WebView2/Browser login popup is still a single shared
                # control across the whole process (only the resulting cookie/session state is
                # isolated per tab) - so only one tab may be actively completing an interactive
                # login at a time. Serialize that here; already-authenticated tabs are unaffected.
                $InteractiveAuthTypes = @("Browser", "WebView2", "Browser-InPrivate", "WebView2-InPrivate")
                $IsInteractiveAuth = $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -in $InteractiveAuthTypes

                if ($IsInteractiveAuth -and $Script:InteractiveLoginInProgress) {
                    "Another tab is completing sign-in, please wait and try again." | Write-LogOutput -LogType WARNING
                    return
                }

                $SiblingTabs = @()
                if ($IsInteractiveAuth) {
                    $Script:InteractiveLoginInProgress = $true
                    $CurrentTabId = $Script:ActiveTabId
                    $SiblingTabs = @($Script:Tabs | Where-Object { $_.Id -ne $CurrentTabId })
                    foreach ($Sibling in $SiblingTabs) {
                        $Sibling.Elements.ButtonConnect.IsEnabled = $false
                    }
                }

                try {
                    if (Test-OmadaConnection) {
                        Test-ConnectionSettings
                    }
                    if ($Script:ConnectionStatus) {
                        Update-QueryList -ForceRefresh
                        Update-DataConnectionList
                        # Auto-connect every other tab that shares this connection identity, reusing
                        # this tab's session (no second login).
                        Sync-MatchingTabConnections -SourceTabId $Script:ActiveTabId -Connect $true
                    }
                }
                finally {
                    if ($IsInteractiveAuth) {
                        $Script:InteractiveLoginInProgress = $false
                        $ReturnToTab = Get-ActiveTabSession
                        foreach ($Sibling in $SiblingTabs) {
                            # Re-derive each sibling's own correct enabled state (Test-ConnectionButton
                            # already knows this) rather than blindly re-enabling it.
                            Set-ActiveTabContext -TabSession $Sibling
                            Test-ConnectionButton
                        }
                        if ($null -ne $ReturnToTab) {
                            Set-ActiveTabContext -TabSession $ReturnToTab
                        }
                    }
                }
            }
            else {
                $DisconnectingTabId = $Script:ActiveTabId
                Set-SqlConnectionState -Status $false
                # Disconnect every other tab that shares this connection identity too.
                Sync-MatchingTabConnections -SourceTabId $DisconnectingTabId -Connect $false
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
