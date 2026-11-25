#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "AdHocQueryDraftStore.Shared.ps1")
}

Describe 'Remove-AdHocQueryDraft' -Tag 'Unit' {
    BeforeEach {
        $script:Store = Join-Path $TestDrive ("{0}.json" -f [guid]::NewGuid())
        $script:DraftLog.Clear()
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text "SELECT 1"
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-2" -Text "SELECT 2"
    }

    It 'Should forget only the given tab''s draft' {
        Remove-AdHocQueryDraft -Path $script:Store -TabId "tab-1"

        @(Get-AdHocQueryDraft -Path $script:Store | ForEach-Object { $_.TabId }) | Should -Be @("tab-2")
    }

    It 'Should delete the store with its last draft' {
        Remove-AdHocQueryDraft -Path $script:Store -TabId "tab-1"
        Remove-AdHocQueryDraft -Path $script:Store -TabId "tab-2"

        Test-Path -LiteralPath $script:Store | Should -BeFalse
    }

    It 'Should forget every draft with -All' {
        Remove-AdHocQueryDraft -Path $script:Store -All

        Test-Path -LiteralPath $script:Store | Should -BeFalse
    }

    It 'Should not rewrite the store for a tab that has no draft' {
        $Before = (Get-Item -LiteralPath $script:Store).LastWriteTimeUtc
        (Get-Item -LiteralPath $script:Store).LastWriteTimeUtc = $Before.AddMinutes(-5)
        $Stamp = (Get-Item -LiteralPath $script:Store).LastWriteTimeUtc

        Remove-AdHocQueryDraft -Path $script:Store -TabId "unknown"

        (Get-Item -LiteralPath $script:Store).LastWriteTimeUtc | Should -Be $Stamp
        @(Get-AdHocQueryDraft -Path $script:Store).Count | Should -Be 2
    }

    It 'Should do nothing when there is no store' {
        $Missing = Join-Path $TestDrive "missing.json"

        { Remove-AdHocQueryDraft -Path $Missing -TabId "tab-1" } | Should -Not -Throw
        { Remove-AdHocQueryDraft -Path $Missing -All } | Should -Not -Throw
        Test-Path -LiteralPath $Missing | Should -BeFalse
    }

    It 'Should warn, without a dialog and without throwing, when the store cannot be written' {
        Mock Write-AdHocQueryDraftStore { throw "disk full" }

        { Remove-AdHocQueryDraft -Path $script:Store -TabId "tab-1" } | Should -Not -Throw

        $script:DraftLog.Count | Should -Be 1
        $script:DraftLog[0].LogType | Should -Be "WARNING"
        $script:DraftLog[0].SkipDialog | Should -BeTrue
        $script:DraftLog[0].Message | Should -Match "disk full"
    }
}
