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
    $script:E2EChoices.Clear()
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

function script:Wait-E2EUntil {
    <#
    .SYNOPSIS
    Pump the dispatcher until $Condition is true, or fail after -TimeoutSeconds.

    .DESCRIPTION
    The scenario-side counterpart to work that no longer finishes inside the click that started it.
    While every backend seam completed inline, an assertion could follow Invoke-E2EExecute directly;
    work that runs off the UI thread instead completes through the 50 ms WebViewCompletionPollTimer,
    which only fires when the dispatcher is pumped - and a scenario running ON the dispatcher thread
    is precisely what stops it from being pumped. So this loop yields (Invoke-E2EFlushDispatcher) and
    re-tests, rather than sleeping.

    Throws on timeout, which E2ECase records as a failure with -Message. Never assert on a result
    without waiting for it first: a bare assertion after an asynchronous action reads as a pass/fail
    of the feature when it is really a race.

    .PARAMETER Condition
    A scriptblock returning something truthy once the wait is over.

    .EXAMPLE
    Wait-E2EUntil { $null -ne $Script:MainForm.Elements.DataGridQueryResult.ItemsSource } -Message "grid populated"
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [double]$TimeoutSeconds = 10,
        [string]$Message = "condition"
    )
    $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        if (& $Condition) {
            return $true
        }
        Invoke-E2EFlushDispatcher
        # A short sleep after the flush, not instead of it: the flush drains work that is already
        # queued, while the poll timer needs wall-clock time to reach its next 50 ms tick. Without
        # this the loop spins hot and starves the very timer it is waiting for.
        Start-Sleep -Milliseconds 25
    }
    # One last chance after the final flush, so a condition that became true during the last pump is
    # not reported as a timeout.
    if (& $Condition) {
        return $true
    }
    throw ("Timed out after {0}s waiting for: {1}" -f $TimeoutSeconds, $Message)
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

function script:New-E2EDeferredTab {
    # A lazily-restored tab: created with -Deferred so it does NOT connect or build its WebView until
    # first viewed - exactly what Restore-TabSessions does for background tabs.
    param(
        [string]$DisplayName = "Deferred",
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
    return (New-TabSession -RestoreFrom $RestoredConfig -AutoConnect -Deferred)
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

function script:Clear-E2EChoices {
    $script:E2EChoices.Clear()
}

function script:Get-E2EChoices {
    param(
        [string]$TitleLike = "*"
    )
    return @($script:E2EChoices | Where-Object { $_.Title -like $TitleLike })
}

function script:Clear-E2EPopups {
    $script:E2EPopupMessages.Clear()
}

function script:Get-E2EPopups {
    param(
        [string]$MessageLike = "*"
    )
    return @($script:E2EPopupMessages | Where-Object { $_ -like $MessageLike })
}

function script:Clear-E2ELog {
    $script:E2ELogMessages.Clear()
}

function script:Get-E2ELogMessages {
    param(
        [string]$MessageLike = "*",
        [string]$LogType = $null   # untyped default so a $null keeps all types
    )
    return @($script:E2ELogMessages | Where-Object {
            $_.Message -like $MessageLike -and
            ([string]::IsNullOrEmpty($LogType) -or $_.LogType -eq $LogType)
        })
}
