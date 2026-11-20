#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Resolve-AdHocQueryDraftRestore.ps1"))
}

Describe 'Resolve-AdHocQueryDraftRestore' -Tag 'Unit' {
    It 'Should put a draft back into its own restored tab (a normal close)' {
        $Draft = [PSCustomObject]@{ TabId = "a"; Text = "SELECT 1" }

        $Plan = Resolve-AdHocQueryDraftRestore -Draft @($Draft) -TabId @("a", "b")

        @($Plan.Attach).Count | Should -Be 1
        $Plan.Attach[0].TabId | Should -Be "a"
        $Plan.Attach[0].Draft | Should -Be $Draft
        @($Plan.Open).Count | Should -Be 0
    }

    It 'Should open a new tab for a draft whose tab was not restored (a crash)' {
        $Draft = [PSCustomObject]@{ TabId = "gone"; Text = "SELECT 1" }

        $Plan = Resolve-AdHocQueryDraftRestore -Draft @($Draft) -TabId @("a")

        @($Plan.Attach).Count | Should -Be 0
        @($Plan.Open).Count | Should -Be 1
        $Plan.Open[0] | Should -Be $Draft
    }

    It 'Should split a mix, keeping the drafts in order' {
        $Drafts = @(
            [PSCustomObject]@{ TabId = "x"; Text = "1" }
            [PSCustomObject]@{ TabId = "a"; Text = "2" }
            [PSCustomObject]@{ TabId = "y"; Text = "3" }
        )

        $Plan = Resolve-AdHocQueryDraftRestore -Draft $Drafts -TabId @("a")

        @($Plan.Attach | ForEach-Object { $_.TabId }) | Should -Be @("a")
        @($Plan.Open | ForEach-Object { $_.TabId }) | Should -Be @("x", "y")
    }

    It 'Should open every draft when no tab is open' {
        $Plan = Resolve-AdHocQueryDraftRestore -Draft @([PSCustomObject]@{ TabId = "a"; Text = "1" }) -TabId @()

        @($Plan.Open).Count | Should -Be 1
    }

    It 'Should not match a blank tab id' {
        $Plan = Resolve-AdHocQueryDraftRestore -Draft @([PSCustomObject]@{ TabId = ""; Text = "1" }) -TabId @("", $null)

        @($Plan.Attach).Count | Should -Be 0
        @($Plan.Open).Count | Should -Be 1
    }

    It 'Should ignore null drafts and plan nothing for none' {
        $Plan = Resolve-AdHocQueryDraftRestore -Draft @($null) -TabId @("a")

        @($Plan.Attach).Count | Should -Be 0
        @($Plan.Open).Count | Should -Be 0
    }
}
