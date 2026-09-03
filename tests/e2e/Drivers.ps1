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

function script:Test-E2EExecuteInFlight {
    # Whether a tab has a query outstanding, read off the completion queue - the same record the app
    # itself uses (Get-ActiveExecuteQueryRequest). Since C1-4 the Execute button stays ENABLED while a
    # query runs, because it is the Cancel button, so IsEnabled is no longer a usable signal for this.
    param($TabSession)
    if ($null -eq $TabSession) { $TabSession = Get-ActiveTabSession }
    return @($Script:PendingWebViewCompletions | Where-Object {
            $_.Description -eq "Execute query" -and $null -ne $_.TabSession -and
            $_.TabSession.Id -eq $TabSession.Id -and -not $_.IsCancelled
        }).Count -gt 0
}

function script:Get-E2EExecuteButtonText {
    param($TabSession)
    $Elements = if ($null -ne $TabSession) { $TabSession.Elements } else { $Script:MainForm.Elements }
    return [string]$Elements.ButtonExecuteQueryText.Text
}

function script:Wait-E2EAppSettled {
    <#
    Pump the dispatcher for a fixed period so work the APP started on its own - a WebView2
    NavigationCompleted callback, a deferred editor push - has landed before a scenario acts.

    Not the same thing as Wait-E2ENoPendingRequests, which waits on a condition. There is no
    condition to wait on here: WebView2 posts its callbacks straight to the dispatcher rather than
    onto the completion queue, and the harness leaves at least one editor task permanently pending,
    so "the queue is empty" never becomes true. Only the first scenario of a run really needs this;
    by the second, startup has long finished.
    #>
    param([int]$SettleMilliseconds = 500)
    $Deadline = [DateTime]::UtcNow.AddMilliseconds($SettleMilliseconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        Invoke-E2EFlushDispatcher
        Start-Sleep -Milliseconds 25
    }
}

function script:Invoke-E2EGetSchemaAndWait {
    # Retrieve the SQL schema and wait for it to land. Since issue #40 Get-SqlSchemaObject dispatches
    # the fetch to a background worker and returns immediately, so anything asserting on the cache,
    # the tree or the setSchema push has to wait for the completion.
    param([double]$TimeoutSeconds = 15)
    Get-SqlSchemaObject
    Wait-E2ENoPendingRequests -TimeoutSeconds $TimeoutSeconds
}

function script:Invoke-E2EConnectAndWait {
    # Connect and let the schema fetch land. Since issue #40 that fetch runs on a background worker,
    # so a scenario asserting on the schema (or merely acting next) must wait for it.
    param([double]$TimeoutSeconds = 15)
    Invoke-E2EConnect
    Wait-E2ENoPendingRequests -TimeoutSeconds $TimeoutSeconds
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
    # Background requests complete immediately again unless a scenario asks for a slow one.
    $script:E2ERequestDelayMs = 0
}

function script:Invoke-E2EExecuteAndWait {
    <#
    Click Execute and wait for the result to land. Since issue #40 the query round-trip runs on a
    background worker, so the grid is NOT populated by the time the click returns - an assertion made
    straight after Invoke-E2EExecute would be testing a race, not the feature. Every scenario that
    cares about the outcome of an execute should go through here.
    #>
    param(
        [double]$TimeoutSeconds = 15
    )
    $Tab = Get-ActiveTabSession
    Invoke-E2EExecute
    Wait-E2EUntil -TimeoutSeconds $TimeoutSeconds -Message "execute to complete" -Condition {
        # The queue, not the button: since C1-4 the Execute button stays enabled during a query
        # because it is the Cancel button. Waiting on the grid instead would hang forever on the
        # perfectly legitimate "query returned no rows" path.
        -not (Test-E2EExecuteInFlight -TabSession $Tab)
    }
    # The request leaves the queue just BEFORE its completion block runs, so one more pump makes sure
    # the completion (grid binding, status bar, button reset) has actually happened.
    Invoke-E2EFlushDispatcher
}

function script:Wait-E2ENoPendingRequests {
    # Drain any background request still in flight, so one scenario's slow query cannot complete in
    # the middle of the next one and repoint the tab under it.
    param([double]$TimeoutSeconds = 15)
    Wait-E2EUntil -TimeoutSeconds $TimeoutSeconds -Message "pending background requests to drain" -Condition {
        @($Script:PendingWebViewCompletions | Where-Object { $null -ne $_.StartedUtc }).Count -eq 0
    }
}

function script:Reset-E2EConnection {
    # Put the active tab back to a disconnected, clean state between scenarios that reuse one tab.
    # Drained first: a request still in flight from the previous scenario would otherwise complete
    # in the middle of this one, repointing the tab context and binding a stale result into its grid.
    # A scenario that leaves work outstanding fails HERE, where the cause is obvious, rather than as
    # a puzzling assertion failure in whichever scenario happens to run next.
    Wait-E2ENoPendingRequests
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
    # Connecting fetches the SQL schema, which is a background request since issue #40. Let it land
    # before the caller acts, so it does not complete in the middle of the caller's first step.
    Wait-E2ENoPendingRequests
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
    # Settle before handing the scenario a clean tab. Since issue #40 a connect leaves a schema
    # request in flight, and a scenario that starts while one is outstanding has it complete
    # underneath its own first action - which repoints the tab context mid-step and makes the
    # scenario's failures unrelated to what it is testing.
    Wait-E2ENoPendingRequests
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
