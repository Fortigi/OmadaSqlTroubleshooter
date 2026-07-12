# In-process UI drivers for the E2E harness. All run on the app's dispatcher thread (the automation
# hook fires at ApplicationIdle), so RaiseEvent invokes handlers synchronously - and because every
# backend/editor seam is mocked to complete inline, an entire connect->execute chain finishes before
# RaiseEvent returns. No dispatcher pumping needed.

function script:Get-E2EElements {
    return $Script:MainForm.Elements
}

function script:Invoke-E2EClick {
    param(
        [string]$ElementName
    )
    $Script:MainForm.Elements.$ElementName.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
}

function script:Set-E2EConnectionFields {
    param(
        [string]$Url = "https://tenant.omada.cloud",
        [string]$Auth = "Browser"
    )
    $Elements = $Script:MainForm.Elements
    $Elements.TextBoxURL.Text = $Url
    $AuthItem = $Elements.ComboBoxSelectAuthenticationOption.Items | Where-Object { $_.Content -eq $Auth } | Select-Object -First 1
    if ($null -ne $AuthItem) {
        $Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $AuthItem
    }
    # Setting .Text directly does not fire the TextBox event that normally derives BaseUrl, so call
    # Set-OmadaUrl explicitly to populate $Script:AppConfig.BaseUrl for a realistic connection.
    Set-OmadaUrl
}

function script:Invoke-E2EConnect {
    Invoke-E2EClick -ElementName "ButtonConnect"
}

function script:Invoke-E2EExecute {
    Invoke-E2EClick -ElementName "ButtonExecuteQuery"
}

function script:Select-E2EQuery {
    param(
        [string]$ContentLike = "*- 100"
    )
    $Elements = $Script:MainForm.Elements
    $Item = $Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like $ContentLike } | Select-Object -First 1
    $Elements.ComboBoxSelectQuery.SelectedItem = $Item
    return $Item
}

function script:Reset-E2EScenario {
    # Return backend fixtures + recorder to their defaults so each scenario starts clean.
    $script:E2ECalls.Clear()
    $script:E2EEditorText = "SELECT 1"
    $script:E2ESelectedText = $null
    $script:E2EQueryList = @([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" })
    $script:E2EResultRows = @([pscustomobject]@{ Col1 = "a"; Col2 = "b" }, [pscustomobject]@{ Col1 = "c"; Col2 = "d" })
    $script:E2ENameClashRows = @()
    $script:E2EConnectionProbeError = $null
    $script:E2EFixtureOverride = $null
    $script:E2EChoiceReturn = $null
}

function script:Reset-E2EConnection {
    # Put the active tab back to a disconnected, clean state between scenarios that reuse one tab.
    if ($Script:ConnectionStatus) {
        Invoke-E2EConnect   # ButtonConnect toggles to Disconnect when already connected
    }
    $Script:MainForm.Elements.DataGridQueryResult.ItemsSource = $null
    # Return the process-global connect gate to its fresh-startup value so a scenario that relies on
    # it (e.g. RestoreReconnect exercising the ReconnectStatus=2 fix) is not masked by a prior
    # scenario having left it at 2.
    $Script:RunTimeConfig.ReconnectStatus = 0
}

function script:New-E2EConnectedTab {
    param(
        [string]$Url = "https://tenant.omada.cloud",
        [string]$Auth = "Browser"
    )
    New-EmptyTabSession | Out-Null   # creates and activates a new tab
    Set-E2EConnectionFields -Url $Url -Auth $Auth
    Invoke-E2EConnect
    return (Get-ActiveTabSession)
}

function script:Invoke-E2EFlushDispatcher {
    # Run all pending Background-and-higher dispatcher work (e.g. a deferred editor re-push) to
    # completion, synchronously, so a scenario can assert on its effect.
    $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function script:New-E2ERestoredTab {
    param(
        [string]$DisplayName = "Restored",
        [string]$Url = "https://tenant.omada.cloud",
        [string]$Auth = "Browser"
    )
    $RestoredConfig = [pscustomobject]@{
        Id                    = ([guid]::NewGuid().Guid)
        DisplayName           = $DisplayName
        BaseUrl               = $Url
        CurrentSqlQuery       = [pscustomobject]@{ DoId = 100; DisplayName = "TestQuery"; FullName = "TestQuery - 100" }
        LastAuthentication    = $Auth
        UserName              = $null
        Password              = $null
        EntraApplicationIdUri = $null
        EntraIdTenantId       = $null
        MyCreatedQueriesOnly  = $false
        MyUpdatedQueriesOnly  = $false
        SavePassword          = $false
        IdentityUserName      = $null
        CurrentDataConnection = [pscustomobject]@{ DoId = 42; DisplayName = "OISES"; FullName = "OISES - 42" }
    }
    return (New-TabSession -RestoreFrom $RestoredConfig -AutoConnect)
}

function script:Reset-E2ETabsToOne {
    # Collapse to a single, disconnected tab so tab-count-sensitive scenarios start from a known state.
    if ($Script:Tabs.Count -eq 0) {
        New-EmptyTabSession | Out-Null
    }
    elseif ($Script:Tabs.Count -gt 1) {
        Close-OtherTabSessions -KeepTabId $Script:Tabs[0].Id
    }
    (Get-TabControlSessions).SelectedItem = $Script:Tabs[0].TabItem
    Reset-E2EConnection
    Reset-E2EScenario
}

function script:Get-E2EActiveTabIndex {
    return $Script:Tabs.IndexOf((Get-ActiveTabSession))
}

function script:Get-E2ECallCount {
    param(
        [string]$MethodLike = "*",
        [string]$UriLike = "*",
        $DataType = $null   # untyped: a [string] default coerces $null to '' and breaks the guard below
    )
    return @($script:E2ECalls | Where-Object {
            $_.Method -like $MethodLike -and $_.Uri -like $UriLike -and
            ($null -eq $DataType -or $_.DataType -eq $DataType)
        }).Count
}
