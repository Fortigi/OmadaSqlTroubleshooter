# Issue #65: "Switching to a not-yet-connected tab connects silently and leaves the tab in an
# in-between state". The silent connect itself is the shared root cause fixed for #64; what these
# scenarios pin down is that the UI is consistent with the connection state in BOTH directions -
# button text, status bar, both dropdowns and the Display name always telling the same story.
#
# New-E2EPersistedTabStore and Initialize-E2ERestoreRun come from scenarios/NoReconnect.ps1, which
# Automation.Entry.ps1 dot-sources first (scenario files load in name order).

function script:Get-E2EUiState {
    <# One snapshot of every element the issue lists as disagreeing with the others. #>
    $Elements = $Script:MainForm.Elements
    return [PSCustomObject]@{
        ConnectionFlag         = [bool]$Script:ConnectionStatus
        ButtonText             = [string]$Elements.ButtonConnectText.Text
        StatusBar              = [string]$Elements.TextBlockStatusBarConnectionStatus.Text
        QueryDropdown          = [bool]$Elements.ComboBoxSelectQuery.IsEnabled
        DataConnectionDropdown = [bool]$Elements.ComboBoxSelectDataConnection.IsEnabled
        DisplayName            = [bool]$Elements.TextBoxDisplayName.IsEnabled
    }
}

E2ESuite -Name "TabConnectionStateConsistency" -Body {
    E2ECase -Name "switching to a restored tab after declining the reconnect prompt connects nothing and shows one consistent disconnected state" -Body {
        Reset-E2ETabsToOne
        New-E2EPersistedTabStore -TabCount 2 | Out-Null
        Initialize-E2ERestoreRun -NoReconnect $false
        $script:E2EChoiceReturn = 1   # decline the "Reconnect?" prompt

        Restore-TabSessions

        E2EAssertEqual 1 (Get-E2EChoices -TitleLike "Reconnect?").Count "the reconnect prompt should have been shown once for the whole batch"

        $RestoredTabs = @($Script:Tabs | Where-Object { $_.DisplayName -like "Persisted*" })
        E2EAssertEqual 2 $RestoredTabs.Count "both persisted tabs should have been restored"

        $SecondTab = $RestoredTabs[1]
        E2EAssertTrue ($SecondTab.Id -ne $Script:ActiveTabId) "the second persisted tab should still be a deferred background tab"

        # The reported repro: selecting a tab that has not connected in this session.
        $script:E2ECalls.Clear()
        (Get-TabControlSessions).SelectedItem = $SecondTab.TabItem
        Invoke-E2EFlushDispatcher

        E2EAssertEqual 0 (Get-E2ECallCount) "switching to a not-yet-connected tab must not issue a single request"

        # And the schema push that follows once that tab's Monaco editor finishes loading must be
        # just as quiet. ReconnectStatus is process-global and is already 3 by now, which is exactly
        # why it was never a usable per-tab gate.
        $Script:RunTimeConfig.ReconnectStatus = 3
        Get-SqlSchemaObject
        E2EAssertEqual 0 (Get-E2ECallCount) "the navigation-completed schema push must not connect the tab either"

        # The in-between state from the issue, element by element.
        $UiState = Get-E2EUiState
        E2EAssertTrue (-not $UiState.ConnectionFlag) "the tab must be disconnected"
        E2EAssertEqual "_Connect" $UiState.ButtonText "the button must read Connect"
        E2EAssertEqual "Disconnected" $UiState.StatusBar "the status bar must read Disconnected, not Connected next to a Connect button"
        E2EAssertTrue (-not $UiState.DataConnectionDropdown) "the data connection dropdown must be disabled while disconnected"
        # The re-enable itself came from Update-QueryList's tail, reached from the WebView2
        # completion block; that is pinned down deterministically in tests/Update-QueryList.Tests.ps1
        # (this harness does not reliably reach the completion block within a scenario's window).
        E2EAssertTrue (-not $UiState.QueryDropdown) "the query dropdown must be disabled while disconnected"
        E2EAssertTrue (-not $UiState.DisplayName) "Display name must be disabled while disconnected, consistent with the dropdowns"
    }

    E2ECase -Name "connecting that tab explicitly produces the complete connected UI, and Disconnect works" -Body {
        Reset-E2ETabsToOne
        New-E2EPersistedTabStore -TabCount 2 | Out-Null
        Initialize-E2ERestoreRun -NoReconnect $false
        $script:E2EChoiceReturn = 1

        Restore-TabSessions

        $RestoredTabs = @($Script:Tabs | Where-Object { $_.DisplayName -like "Persisted*" })
        $SecondTab = $RestoredTabs[1]
        (Get-TabControlSessions).SelectedItem = $SecondTab.TabItem
        Invoke-E2EFlushDispatcher

        # The user does what the in-between state made impossible: click Connect.
        Invoke-E2EConnect

        $ConnectedState = Get-E2EUiState
        E2EAssertTrue $ConnectedState.ConnectionFlag "clicking Connect must connect the tab"
        E2EAssertEqual "Dis_connect" $ConnectedState.ButtonText "the button must switch to Disconnect"
        E2EAssertEqual "Connected" $ConnectedState.StatusBar "the status bar must read Connected"
        E2EAssertTrue $ConnectedState.QueryDropdown "the query dropdown must be enabled once connected"
        E2EAssertTrue $ConnectedState.DataConnectionDropdown "the data connection dropdown must be enabled once connected"
        E2EAssertTrue $ConnectedState.DisplayName "Display name must be enabled once connected"

        # ... and the tab can actually be disconnected again, which the in-between state prevented.
        Invoke-E2EConnect

        $DisconnectedState = Get-E2EUiState
        E2EAssertTrue (-not $DisconnectedState.ConnectionFlag) "clicking Disconnect must disconnect the tab"
        E2EAssertEqual "_Connect" $DisconnectedState.ButtonText "the button must return to Connect"
        E2EAssertEqual "Disconnected" $DisconnectedState.StatusBar "the status bar must return to Disconnected"
        E2EAssertTrue (-not $DisconnectedState.QueryDropdown) "the query dropdown must be disabled again after disconnecting"
        E2EAssertTrue (-not $DisconnectedState.DataConnectionDropdown) "the data connection dropdown must be disabled again after disconnecting"
        E2EAssertTrue (-not $DisconnectedState.DisplayName) "Display name must be disabled again after disconnecting"
    }
}
