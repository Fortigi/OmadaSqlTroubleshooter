#Requires -Version 7.0
# Issue #40's authentication policy, expressed as tests.
#
# The policy is: interactive authentication happens on the UI thread, or it does not happen.
# OmadaWeb.PS authenticates by opening a WinForms modal on whatever thread calls it, and from a
# worker that dialog would have no owner window - not modal to this app, possibly behind the main
# window, with the app fully interactive behind it. So a request only goes to a worker when the
# session is already authenticated and is not asking to authenticate again.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaBackgroundRequestEligible.ps1")
}

Describe "Test-OmadaBackgroundRequestEligible" {
    It "allows a connected tab whose request does not force authentication" {
        $Script:ConnectionStatus = $true

        Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $false } | Should -BeTrue
    }

    It "allows a connected tab whose request omits ForceAuthentication entirely" {
        $Script:ConnectionStatus = $true

        Test-OmadaBackgroundRequestEligible -Parameters @{ Uri = "https://tenant.omada.cloud/probe" } | Should -BeTrue
    }

    It "refuses a tab that is not connected" {
        # Not connected means no successful Test-OmadaConnection on the UI thread, so no cookie on
        # disk for this SessionKey - and a worker with an empty session table would go looking for
        # one by opening a login window.
        $Script:ConnectionStatus = $false

        Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $false } | Should -BeFalse
    }

    It "refuses a request that asks to re-authenticate, even on a connected tab" {
        # ForceAuthentication exists to make OmadaWeb.PS bypass its cookie cache and authenticate
        # again - which is a request to open the login window. That has to happen where the window
        # can have an owner.
        $Script:ConnectionStatus = $true

        Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $true } | Should -BeFalse
    }

    It "refuses on both counts at once" {
        $Script:ConnectionStatus = $false

        Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $true } | Should -BeFalse
    }

    It "requires the Parameters argument" {
        # Asserted as metadata: calling without a mandatory parameter prompts, which hangs an
        # unattended run.
        (Get-Command Test-OmadaBackgroundRequestEligible).Parameters["Parameters"].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory } | Should -Contain $true
    }
}
