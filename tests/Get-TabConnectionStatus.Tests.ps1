#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Get-TabConnectionStatus.ps1"))
}

Describe 'Get-TabConnectionStatus' -Tag 'Unit' {
    BeforeEach {
        $Script:ActiveTabId = "active"
    }

    It 'Should read the live state for the active tab, not its stale copy' {
        $Script:ConnectionStatus = $true

        Get-TabConnectionStatus -TabSession ([PSCustomObject]@{ Id = "active"; ConnectionStatus = $false }) | Should -BeTrue
    }

    It 'Should report a disconnected active tab' {
        $Script:ConnectionStatus = $false

        Get-TabConnectionStatus -TabSession ([PSCustomObject]@{ Id = "active"; ConnectionStatus = $true }) | Should -BeFalse
    }

    It 'Should read a background tab''s own state (<State>)' -ForEach @(
        @{ State = $true }
        @{ State = $false }
    ) {
        $Script:ConnectionStatus = -not $State

        Get-TabConnectionStatus -TabSession ([PSCustomObject]@{ Id = "other"; ConnectionStatus = $State }) | Should -Be $State
    }
}
