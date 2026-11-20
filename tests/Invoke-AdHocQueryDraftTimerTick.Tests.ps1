#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Invoke-AdHocQueryDraftTimerTick.ps1"))

    $script:Synced = [System.Collections.Generic.List[object]]::new()
    function Sync-AdHocQueryDraft { param($TabSession) $script:Synced.Add($TabSession.Id) }
}

Describe 'Invoke-AdHocQueryDraftTimerTick' -Tag 'Unit' {
    BeforeEach {
        $script:Synced.Clear()
        $Script:Tabs = @(
            [PSCustomObject]@{ Id = "pending"; DraftPending = $true }
            [PSCustomObject]@{ Id = "clean"; DraftPending = $false }
            [PSCustomObject]@{ Id = "untracked" }
            $null
            [PSCustomObject]@{ Id = "pending-2"; DraftPending = $true }
        )
    }

    It 'Should write the pending tabs on every 40th tick (two seconds)' {
        Invoke-AdHocQueryDraftTimerTick -TickCount 40

        @($script:Synced) | Should -Be @("pending", "pending-2")
    }

    It 'Should do nothing on the ticks in between (<Tick>)' -ForEach @(
        @{ Tick = 1 }
        @{ Tick = 20 }
        @{ Tick = 39 }
        @{ Tick = 41 }
    ) {
        Invoke-AdHocQueryDraftTimerTick -TickCount $Tick

        $script:Synced.Count | Should -Be 0
    }

    It 'Should honour another interval' {
        Invoke-AdHocQueryDraftTimerTick -TickCount 6 -Interval 3

        $script:Synced.Count | Should -Be 2
    }

    It 'Should refuse an interval below one' {
        { Invoke-AdHocQueryDraftTimerTick -TickCount 6 -Interval 0 } | Should -Throw
    }
}
