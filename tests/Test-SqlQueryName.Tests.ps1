#Requires -Version 7.0
# The local checks on a name typed for a rename or a save-as-new, before anything reaches the tenant.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Test-SqlQueryName.ps1"))
}

Describe 'Test-SqlQueryName' -Tag 'Unit' {
    It 'Should accept a new, unused name' {
        $Result = Test-SqlQueryName -Name "Accounts per system" -ExistingNames @("Other")

        $Result.IsValid | Should -BeTrue
        $Result.IsUnchanged | Should -BeFalse
        $Result.Name | Should -Be "Accounts per system"
        $Result.Message | Should -BeNullOrEmpty
    }

    It 'Should trim the name' {
        (Test-SqlQueryName -Name "  Accounts  ").Name | Should -Be "Accounts"
    }

    It 'Should refuse an empty name (<Case>)' -ForEach @(
        @{ Case = 'null'; Name = $null }
        @{ Case = 'empty'; Name = '' }
        @{ Case = 'blank'; Name = '   ' }
    ) {
        $Result = Test-SqlQueryName -Name $Name

        $Result.IsValid | Should -BeFalse
        $Result.Message | Should -Match 'empty'
    }

    It 'Should refuse the TMP_ prefix of the temporary query objects, in any case' -ForEach @(
        @{ Name = 'TMP_mine' }
        @{ Name = 'tmp_mine' }
        @{ Name = '  TMP_x' }
    ) {
        $Result = Test-SqlQueryName -Name $Name

        $Result.IsValid | Should -BeFalse
        $Result.Message | Should -Match "TMP_"
    }

    It 'Should accept a name that only contains TMP_ further on' {
        (Test-SqlQueryName -Name "My TMP_ query").IsValid | Should -BeTrue
    }

    It 'Should refuse a name another known query has, ignoring case and blanks' {
        $Result = Test-SqlQueryName -Name "accounts" -ExistingNames @("Other", " Accounts ")

        $Result.IsValid | Should -BeFalse
        $Result.Message | Should -Match "already exists"
        $Result.Message | Should -Match "'accounts'"
    }

    It 'Should report a rename to the same name as unchanged rather than as a clash' {
        $Result = Test-SqlQueryName -Name "Accounts" -ExistingNames @("Accounts") -CurrentName "Accounts"

        $Result.IsValid | Should -BeTrue
        $Result.IsUnchanged | Should -BeTrue
    }

    It 'Should allow a rename that only changes the case' {
        $Result = Test-SqlQueryName -Name "ACCOUNTS" -ExistingNames @("Accounts") -CurrentName "Accounts"

        $Result.IsValid | Should -BeTrue
        $Result.IsUnchanged | Should -BeFalse
        $Result.Name | Should -Be "ACCOUNTS"
    }

    It 'Should still refuse a rename onto another query''s name' {
        $Result = Test-SqlQueryName -Name "Other" -ExistingNames @("Accounts", "Other") -CurrentName "Accounts"

        $Result.IsValid | Should -BeFalse
        $Result.IsUnchanged | Should -BeFalse
    }

    It 'Should ignore blank entries in the known names' {
        (Test-SqlQueryName -Name "Accounts" -ExistingNames @($null, "", "  ")).IsValid | Should -BeTrue
    }
}
