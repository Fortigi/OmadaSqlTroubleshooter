#Requires -Version 7.0
# Eligibility settled by observation rather than assumption.
#
# Issue #40 assumed a tab that authenticated on the UI thread could also be served from a worker,
# because OmadaWeb.PS keeps an encrypted cookie cache on disk that a fresh worker would load. Live
# testing disproved it: with some tenants and authentication options the worker's own OmadaWeb.PS
# cannot establish a session, and every background request fails. The assumption was never testable -
# the mock replaces Invoke-OmadaRestMethod outright, so no authentication happens under test - so it
# is now settled by watching what actually happens.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Disable-OmadaBackgroundRequest.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaBackgroundRequestEligible.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    $script:PoolClosures = 0
    function Close-OmadaRequestPool { $script:PoolClosures++ }

    function script:Initialize-DisableTestState {
        $script:LogMessages.Clear()
        $script:PoolClosures = 0
        $Script:OmadaBackgroundRequestsDisabled = $false
        $Script:ConnectionStatus = $true
    }
}

Describe "Disable-OmadaBackgroundRequest" {
    BeforeEach { Initialize-DisableTestState }

    It "stops further requests being dispatched" {
        Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $false } | Should -BeTrue

        Disable-OmadaBackgroundRequest -Reason "no session in the worker"

        Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $false } | Should -BeFalse
    }

    It "warns once, and says what the user actually loses" {
        # Not a dialog, and not repeated per query: nothing is broken from the user's point of view -
        # their query is about to run on the UI thread and succeed. What they lose is the window
        # staying responsive, which is worth one line rather than a popup.
        Disable-OmadaBackgroundRequest -Reason "no session in the worker"
        Disable-OmadaBackgroundRequest -Reason "no session in the worker"
        Disable-OmadaBackgroundRequest -Reason "something else"

        $Warnings = @($script:LogMessages | Where-Object { $_.LogType -eq "WARNING" })
        $Warnings.Count | Should -Be 1
        $Warnings[0].Message | Should -Match "UI thread"
        $Warnings[0].Message | Should -Match "no session in the worker"
    }

    It "releases the pool's worker threads, once" {
        Disable-OmadaBackgroundRequest -Reason "no session in the worker"
        Disable-OmadaBackgroundRequest -Reason "no session in the worker"

        $script:PoolClosures | Should -Be 1
    }

    It "is checked before the connection state, so a connected tab is still refused" {
        # The discriminating case: the tab IS connected and the request is not forcing
        # authentication, so every other gate says yes. Only the observed failure stops it.
        $Script:ConnectionStatus = $true
        Disable-OmadaBackgroundRequest -Reason "no session in the worker"

        Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $false } | Should -BeFalse
    }
}
