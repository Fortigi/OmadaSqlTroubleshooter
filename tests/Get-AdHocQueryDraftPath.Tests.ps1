#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "AdHocQueryDraftStore.Shared.ps1")
}

Describe 'Get-AdHocQueryDraftPath' -Tag 'Unit' {
    It 'Should keep the drafts next to the tab sessions, in the config folder' {
        Get-AdHocQueryDraftPath -AppDataFolder "base" | Should -Be ([System.IO.Path]::Combine("base", "config", "adhoc-query-drafts.json"))
    }

    It 'Should default to the application data folder of this session' {
        $Script:RunTimeConfig = [PSCustomObject]@{ AppDataFolder = "appdata" }

        Get-AdHocQueryDraftPath | Should -Be ([System.IO.Path]::Combine("appdata", "config", "adhoc-query-drafts.json"))
    }
}
