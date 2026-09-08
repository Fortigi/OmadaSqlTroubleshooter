#Requires -Version 7.0
# From a live session (issue #40 test 1): background execution ran for nine minutes, the application
# sat idle for seventy, and the first query after the idle failed because the session had expired -
# which a worker cannot recover from, having no way to sign in. The UI thread re-authenticated
# seconds later and every subsequent query worked, but background execution stayed off for the rest
# of the session, so the remaining four minutes blocked the window for no reason.
#
# The disable was written as one-way on the reasoning that a worker's ability to authenticate is a
# property of the tenant rather than of the moment. The log disproved that: the commonest cause is an
# expired session, which is entirely of the moment.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Disable-OmadaBackgroundRequest.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaBackgroundRequestEligible.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    $script:PoolClosures = 0
    function Close-OmadaRequestPool { $script:PoolClosures++ }

    function script:Initialize-ReenableTestState {
        $script:LogMessages.Clear()
        $script:PoolClosures = 0
        $Script:OmadaBackgroundRequestsDisabled = $false
        $Script:OmadaBackgroundRequestWarned = $false
        $Script:OmadaBackgroundRequestReenableCount = 0
        $Script:OmadaBackgroundRequestReenableLimit = 3
        $Script:OmadaBackgroundRequestReenableExhausted = $false
        $Script:ConnectionStatus = $true
    }

    function script:Test-Eligible { return Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $false } }
}

Describe "Enable-OmadaBackgroundRequest" {
    BeforeEach { Initialize-ReenableTestState }

    It "offers a worker the next query once one has succeeded on the UI thread" {
        # The whole point. An expired session is not a permanent property of the tenant.
        Disable-OmadaBackgroundRequest -Reason "worker could not sign in"
        Test-Eligible | Should -BeFalse

        Enable-OmadaBackgroundRequest

        Test-Eligible | Should -BeTrue
    }

    It "says so in the log, where the warning was, without a dialog" {
        Disable-OmadaBackgroundRequest -Reason "worker could not sign in"
        $script:LogMessages.Clear()

        Enable-OmadaBackgroundRequest

        $Private:Info = @($script:LogMessages | Where-Object { $_.LogType -eq "INFO" })
        $Private:Info.Count | Should -Be 1
        $Private:Info[0].Message | Should -Match "available again"
    }

    It "does nothing when background execution was never switched off" {
        Enable-OmadaBackgroundRequest

        @($script:LogMessages).Count | Should -Be 0
        Test-Eligible | Should -BeTrue
    }

    It "stops trying after the limit, so a genuinely broken worker settles down" {
        # The other half of the trade. If the worker can never run here - no WebView2 runtime - each
        # re-enable costs one failed request. Three across a whole session is acceptable; one per
        # query is not.
        1..4 | ForEach-Object {
            Disable-OmadaBackgroundRequest -Reason "worker cannot run here"
            Enable-OmadaBackgroundRequest
        }

        Test-Eligible | Should -BeFalse
        $Script:OmadaBackgroundRequestReenableCount | Should -Be 3
    }

    It "explains the give-up once, at DEBUG" {
        1..5 | ForEach-Object {
            Disable-OmadaBackgroundRequest -Reason "worker cannot run here"
            Enable-OmadaBackgroundRequest
        }

        $Private:GiveUp = @($script:LogMessages | Where-Object { $_.LogType -eq "DEBUG" -and $_.Message -match "leaving it off" })
        $Private:GiveUp.Count | Should -Be 1
    }

    It "lets the pool be rebuilt, because disabling closed it" {
        # Close-OmadaRequestPool nulls the pool and Initialize-OmadaRequestPool recreates one on
        # demand, so re-enabling needs nothing beyond clearing the flag - but if that ever changes,
        # this is where it shows up.
        Disable-OmadaBackgroundRequest -Reason "worker could not sign in"
        $script:PoolClosures | Should -Be 1

        Enable-OmadaBackgroundRequest

        Test-Eligible | Should -BeTrue
    }

    It "still refuses while the tab is disconnected" {
        # Re-enabling is about the worker, not about the tab. A disconnected tab has nothing to run.
        Disable-OmadaBackgroundRequest -Reason "worker could not sign in"
        Enable-OmadaBackgroundRequest
        $Script:ConnectionStatus = $false

        Test-Eligible | Should -BeFalse
    }
}

Describe "The fallback warning matches what actually happens" {
    BeforeEach { Initialize-ReenableTestState }

    It "does not promise that background execution is gone for the session" {
        # It used to say "for the rest of this session", which stopped being true the moment the
        # disable became recoverable - and a message that overstates the damage is worse than none.
        Disable-OmadaBackgroundRequest -Reason "worker could not sign in"

        $Private:Warning = @($script:LogMessages | Where-Object { $_.LogType -eq "WARNING" })[0]
        $Private:Warning.Message | Should -Not -Match "rest of this session"
        $Private:Warning.Message | Should -Match "offered again"
    }

    It "still says what the user actually loses, and why" {
        Disable-OmadaBackgroundRequest -Reason "worker could not sign in"

        $Private:Warning = @($script:LogMessages | Where-Object { $_.LogType -eq "WARNING" })[0]
        $Private:Warning.Message | Should -Match "will not stay responsive"
        $Private:Warning.Message | Should -Match "worker could not sign in"
    }

    It "warns once per session, not once per fallback" {
        # Recoverable means this can be reached several times. Repeating the same warning each time
        # would be noise about a condition the user has been told about and cannot act on.
        Disable-OmadaBackgroundRequest -Reason "first"
        Enable-OmadaBackgroundRequest
        Disable-OmadaBackgroundRequest -Reason "second"
        Enable-OmadaBackgroundRequest
        Disable-OmadaBackgroundRequest -Reason "third"

        @($script:LogMessages | Where-Object { $_.LogType -eq "WARNING" }).Count | Should -Be 1
    }

    It "still records the later fallbacks, at DEBUG" {
        Disable-OmadaBackgroundRequest -Reason "first"
        Enable-OmadaBackgroundRequest
        Disable-OmadaBackgroundRequest -Reason "second"

        @($script:LogMessages | Where-Object { $_.LogType -eq "DEBUG" -and $_.Message -match "second" }).Count | Should -Be 1
    }
}

Describe "The re-enable is driven by a UI-thread success" {
    It "is called only on the already-on-the-UI-thread success path" {
        # A background success cannot be evidence that the UI thread has a session - and background
        # is disabled at that point anyway, so there is nothing to re-enable.
        $Private:Source = Get-Content -Path (Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private") "Invoke-ExecuteQuery.ps1") -Raw

        $Private:Source | Should -Match '(?s)if \(\$AlreadyOnUiThread\) \{\s*Enable-OmadaBackgroundRequest'
    }
}
