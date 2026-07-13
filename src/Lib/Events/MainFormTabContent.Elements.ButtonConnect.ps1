$Script:MainForm.Elements.ButtonConnect.Add_Click({
        param($ClickSender, $ClickArgs)
        try {
            $_ | Show-EventInfo

            # This handler acts on the ambient active-tab context ($Script:MainForm.Elements, etc.),
            # which an async event can leave pointing at a different (background) tab. Re-activate the
            # tab whose OWN Connect button was clicked so Connect/Disconnect always acts on the visible
            # tab the user clicked - otherwise the disconnect updates an off-screen tab and the visible
            # tab looks stuck "Connected" (the "cannot disconnect" bug).
            $OwningConnectTab = $Script:Tabs | Where-Object { $_.Elements.ButtonConnect -eq $ClickSender } | Select-Object -First 1
            if ($null -ne $OwningConnectTab -and $OwningConnectTab.Id -ne $Script:ActiveTabId) {
                Set-ActiveTabContext -TabSession $OwningConnectTab
            }

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
                # Each tab connects/disconnects on its own. Tabs that share a connection pool
                # (tenant + authentication + credentials, via the shared SessionKey set in
                # Test-OmadaConnection) reuse one another's live Omada session while connected, but
                # disconnecting one only disconnects that tab - the others stay connected.
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
