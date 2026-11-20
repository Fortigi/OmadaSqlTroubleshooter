#Requires -Version 7.0
# One draft per tab, written atomically, read back exactly.

BeforeAll {
    . (Join-Path $PSScriptRoot "AdHocQueryDraftStore.Shared.ps1")
}

Describe 'Save-AdHocQueryDraft' -Tag 'Unit' {
    BeforeEach {
        $script:Store = Join-Path $TestDrive ("{0}.json" -f [guid]::NewGuid())
    }

    It 'Should create the store, and its folder, for the first draft' {
        $Nested = Join-Path $TestDrive ([System.IO.Path]::Combine("new", "config", "drafts.json"))

        Save-AdHocQueryDraft -Path $Nested -TabId "tab-1" -Text "SELECT 1"

        Test-Path -LiteralPath $Nested | Should -BeTrue
        $Draft = @(Get-AdHocQueryDraft -Path $Nested)
        $Draft.Count | Should -Be 1
        $Draft[0].TabId | Should -Be "tab-1"
        $Draft[0].Text | Should -Be "SELECT 1"
    }

    It 'Should keep the text exactly, line breaks, quotes and unicode included' {
        $Text = "SELECT 'a''b' AS [x]`r`n-- é ✓`n`tFROM t"

        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text $Text

        (Get-AdHocQueryDraft -Path $script:Store).Text | Should -BeExactly $Text
    }

    It 'Should replace the earlier draft of the same tab' {
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text "SELECT 1"
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text "SELECT 2"

        $Draft = @(Get-AdHocQueryDraft -Path $script:Store)
        $Draft.Count | Should -Be 1
        $Draft[0].Text | Should -Be "SELECT 2"
    }

    It 'Should keep the drafts of other tabs' {
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text "SELECT 1"
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-2" -Text "SELECT 2"

        @(Get-AdHocQueryDraft -Path $script:Store | Sort-Object TabId | ForEach-Object { $_.TabId }) | Should -Be @("tab-1", "tab-2")
    }

    It 'Should keep the tab settings that come with a draft' {
        $Config = ConvertTo-AdHocQueryDraftTabConfig -TabId "tab-1" -AppConfig ([PSCustomObject]@{ BaseUrl = "https://tenant.omada.cloud"; UserName = "user" }) -DisplayName "Mine"

        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text "SELECT 1" -TabConfig $Config

        $Draft = Get-AdHocQueryDraft -Path $script:Store
        $Draft.TabConfig.BaseUrl | Should -Be "https://tenant.omada.cloud"
        $Draft.TabConfig.UserName | Should -Be "user"
        $Draft.TabConfig.DisplayName | Should -Be "Mine"
        $Draft.TabConfig.Id | Should -Be "tab-1"
    }

    It 'Should record when the draft was kept, in UTC' {
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text "SELECT 1"

        # Read from the file itself: ConvertFrom-Json turns an ISO 8601 string into a [DateTime].
        $Raw = Get-Content -LiteralPath $script:Store -Raw
        $Raw | Should -Match '"SavedAt":\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z"'

        $Stamp = [regex]::Match($Raw, '"SavedAt":\s*"([^"]+)"').Groups[1].Value
        $SavedAt = [DateTime]::Parse($Stamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        ([DateTime]::UtcNow - $SavedAt).TotalMinutes | Should -BeLessThan 5
    }

    It 'Should leave no temporary file behind' {
        Save-AdHocQueryDraft -Path $script:Store -TabId "tab-1" -Text "SELECT 1"

        Test-Path -LiteralPath ("{0}.tmp" -f $script:Store) | Should -BeFalse
    }
}
