#Requires -Version 7.0
# Reading the drafts must never stop the application from starting.

BeforeAll {
    . (Join-Path $PSScriptRoot "AdHocQueryDraftStore.Shared.ps1")
}

Describe 'Get-AdHocQueryDraft' -Tag 'Unit' {
    BeforeEach {
        $script:Store = Join-Path $TestDrive ("{0}.json" -f [guid]::NewGuid())
        $script:DraftLog.Clear()
    }

    It 'Should return nothing when there is no store' {
        @(Get-AdHocQueryDraft -Path $script:Store).Count | Should -Be 0
        $script:DraftLog.Count | Should -Be 0
    }

    It 'Should return nothing, with a warning but no dialog, for a corrupt store' {
        Set-Content -LiteralPath $script:Store -Value "{ not json"

        @(Get-AdHocQueryDraft -Path $script:Store).Count | Should -Be 0
        $script:DraftLog.Count | Should -Be 1
        $script:DraftLog[0].LogType | Should -Be "WARNING"
        $script:DraftLog[0].SkipDialog | Should -BeTrue
        $script:DraftLog[0].Message | Should -Match ([regex]::Escape($script:Store))
    }

    It 'Should leave a corrupt store in place for inspection' {
        Set-Content -LiteralPath $script:Store -Value "{ not json"

        $null = Get-AdHocQueryDraft -Path $script:Store

        Test-Path -LiteralPath $script:Store | Should -BeTrue
    }

    It 'Should drop entries without a tab id or without text' {
        @{
            Version = 1
            Drafts  = @(
                @{ TabId = "keep"; Text = "SELECT 1" }
                @{ TabId = ""; Text = "SELECT 2" }
                @{ TabId = "no-text"; Text = "  " }
                @{ Text = "SELECT 3" }
            )
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:Store

        $Draft = @(Get-AdHocQueryDraft -Path $script:Store)
        $Draft.Count | Should -Be 1
        $Draft[0].TabId | Should -Be "keep"
    }

    It 'Should read a store holding a single draft' {
        '{ "Version": 1, "Drafts": { "TabId": "only", "Text": "SELECT 1" } }' | Set-Content -LiteralPath $script:Store

        (Get-AdHocQueryDraft -Path $script:Store).TabId | Should -Be "only"
    }
}
