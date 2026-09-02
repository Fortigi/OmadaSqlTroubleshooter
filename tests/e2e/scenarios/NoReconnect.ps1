# Issue #64: "-NoReconnect does not prevent connecting - the tab connects anyway via the unguarded
# schema push". These scenarios drive the REAL startup restore path (Restore-TabSessions ->
# New-TabSession -Deferred -> Complete-TabMaterialization -> Initialize-WebViewForTab) against a
# persisted tab store, and assert on the call recorder that NOTHING reached the tenant.
#
# The Start menu shortcut keeping -NoReconnect is by design (see the maintainer's scope decision on
# the issue), so what is under test here is only the second half: that -NoReconnect - and a declined
# reconnect prompt - really means "no connection is made on startup at all".

function script:New-E2EPersistedTabStore {
    <#
    Writes a tabs.clixml into the run's throwaway AppData folder, in exactly the shape
    Save-TabSessions produces, so Restore-TabSessions restores real persisted tabs. Built here
    rather than via Save-TabSessions so the store's contents are deterministic and independent of
    whatever the previous scenario left in the live tabs.
    #>
    param(
        [int]$TabCount = 1,
        [string]$Url = "https://tenant.omada.cloud",
        [string]$Auth = "Browser"
    )

    $TabConfigs = @(
        1..$TabCount | ForEach-Object {
            [PSCustomObject]@{
                Id                    = ([guid]::NewGuid().Guid)
                DisplayName           = "Persisted{0}" -f $_
                BaseUrl               = $Url
                CurrentSqlQuery       = [PSCustomObject]@{ DoId = 100; DisplayName = "TestQuery"; FullName = "TestQuery - 100" }
                LastAuthentication    = $Auth
                UserName              = $null
                Password              = $null
                EntraApplicationIdUri = $null
                EntraIdTenantId       = $null
                MyCreatedQueriesOnly  = $false
                MyUpdatedQueriesOnly  = $false
                SavePassword          = $false
                IdentityUserName      = $null
                CurrentDataConnection = [PSCustomObject]@{ DoId = 42; DisplayName = "OISES"; FullName = "OISES - 42" }
            }
        }
    )

    $TabsPath = Join-Path $Script:RunTimeConfig.AppDataFolder -ChildPath "config\tabs.clixml"
    New-Item -Path (Split-Path $TabsPath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    [PSCustomObject]@{
        Tabs        = $TabConfigs
        ActiveTabId = $TabConfigs[0].Id
    } | Export-Clixml -Path $TabsPath -Force

    return $TabConfigs
}

function script:Initialize-E2ERestoreRun {
    <#
    Puts the process-global startup switches back to what a fresh launch has, so Restore-TabSessions
    behaves as it does on startup rather than inheriting a previous scenario's state.
    #>
    param(
        [bool]$NoReconnect
    )
    $Script:RunTimeConfig.ResetRequested = $false
    $Script:RunTimeConfig.NoReconnect = $NoReconnect
    $Script:RunTimeConfig.ReconnectStatus = 0
    Clear-E2EChoices
    $script:E2ECalls.Clear()
}

E2ESuite -Name "NoReconnectStartup" -Body {
    E2ECase -Name "restoring a persisted tab with -NoReconnect makes no request and leaves the tab disconnected" -Body {
        Reset-E2ETabsToOne
        New-E2EPersistedTabStore -TabCount 1 | Out-Null
        Initialize-E2ERestoreRun -NoReconnect $true

        Restore-TabSessions

        E2EAssertEqual 0 (Get-E2EChoices -TitleLike "Reconnect?").Count "-NoReconnect must suppress the reconnect prompt (this part is by design)"
        E2EAssertEqual 0 (Get-E2ECallCount) "restoring under -NoReconnect must not issue a single request to the tenant"

        $RestoredTab = Get-ActiveTabSession
        E2EAssertTrue ($RestoredTab.DisplayName -like "Persisted*") "the persisted tab should be the active tab after restore"
        E2EAssertTrue (-not $Script:ConnectionStatus) "the restored tab must be disconnected"
        E2EAssertEqual "Disconnected" ([string]$Script:MainForm.Elements.TextBlockStatusBarConnectionStatus.Text) "the status bar must read Disconnected"
    }

    E2ECase -Name "the schema push that runs when Monaco finishes loading does not connect a restored tab" -Body {
        # The discriminating case for issue #64. Restore-TabSessions itself was already quiet; the
        # connection was established afterwards, from Initialize-WebViewForTab's NavigationCompleted
        # handler, which calls Get-SqlSchemaObject for every tab whose editor has just loaded. That
        # handler is driven by real WebView2 navigation, so it is invoked directly here to make the
        # assertion deterministic rather than dependent on WebView2 timing.
        Reset-E2ETabsToOne
        New-E2EPersistedTabStore -TabCount 1 | Out-Null
        Initialize-E2ERestoreRun -NoReconnect $true

        Restore-TabSessions

        # ReconnectStatus is process-global and the navigation handler sets it to 3 as soon as ANY
        # tab's editor has loaded - so reproduce that, since it is precisely the value that made the
        # old ReconnectStatus -eq 1 gate useless.
        $Script:RunTimeConfig.ReconnectStatus = 3
        $script:E2ECalls.Clear()

        Get-SqlSchemaObject

        E2EAssertEqual 0 (Get-E2ECallCount) "Get-SqlSchemaObject must not request anything for a tab that is not connected"
        E2EAssertTrue (-not $Script:ConnectionStatus) "the tab must still be disconnected after the navigation-completed schema push"
    }

    E2ECase -Name "declining the reconnect prompt shows the prompt and still connects nothing" -Body {
        Reset-E2ETabsToOne
        New-E2EPersistedTabStore -TabCount 1 | Out-Null
        Initialize-E2ERestoreRun -NoReconnect $false
        # Restore-TabSessions maps the right-hand button (1) to "do not reconnect".
        $script:E2EChoiceReturn = 1

        Restore-TabSessions

        E2EAssertEqual 1 (Get-E2EChoices -TitleLike "Reconnect?").Count "without -NoReconnect the reconnect prompt must be shown"
        E2EAssertEqual 0 (Get-E2ECallCount) "answering 'no' to the reconnect prompt must not issue a single request"

        $Script:RunTimeConfig.ReconnectStatus = 3
        Get-SqlSchemaObject
        E2EAssertEqual 0 (Get-E2ECallCount) "the navigation-completed schema push must stay quiet after a declined reconnect"
        E2EAssertTrue (-not $Script:ConnectionStatus) "the tab must remain disconnected after declining the prompt"
        E2EAssertEqual "Disconnected" ([string]$Script:MainForm.Elements.TextBlockStatusBarConnectionStatus.Text) "the status bar must read Disconnected"
    }

    E2ECase -Name "accepting the reconnect prompt still connects the tab and retrieves its schema" -Body {
        # The guard must not be a blanket 'never fetch': the accepted-reconnect path is the one that
        # legitimately connects, and it must keep working.
        Reset-E2ETabsToOne
        New-E2EPersistedTabStore -TabCount 1 | Out-Null
        Initialize-E2ERestoreRun -NoReconnect $false
        $script:E2EChoiceReturn = 2
        # "Retrieves its schema" is only observable from a COLD cache. The schema cache is keyed by
        # pool SessionKey + data connection and lives for the whole session, and every scenario in
        # this run connects to the same tenant with the same identity - so by the time this one runs
        # the key is warm and a correct connect issues no request at all. Emptying it here is what
        # makes the assertion about the connect path rather than about which scenarios ran first.
        $Script:SqlSchemaCache = @{}

        Restore-TabSessions
        # The schema fetch a successful reconnect triggers is a background request since issue #40,
        # so the call it makes is not on the record until the request has actually been issued.
        Wait-E2ENoPendingRequests

        E2EAssertEqual 1 (Get-E2EChoices -TitleLike "Reconnect?").Count "the reconnect prompt should be shown"
        E2EAssertTrue ($Script:ConnectionStatus) "accepting the prompt must connect the restored tab"
        E2EAssertTrue ((Get-E2ECallCount) -ge 1) "an accepted reconnect is expected to talk to the tenant"
        E2EAssertTrue ((Get-E2ECallCount -MethodLike "POST" -UriLike "*getsqlschema*") -ge 1) "a connected tab must still retrieve its SQL schema (the guard must not block the connect path)"
    }
}
