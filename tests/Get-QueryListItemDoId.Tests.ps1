#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Get-QueryListItemDoId.ps1"))
}

Describe 'Get-QueryListItemDoId' -Tag 'Unit' {
    It 'Should read the id after the separator' {
        Get-QueryListItemDoId -Content "Accounts - 1024" | Should -Be "1024"
    }

    It 'Should use the LAST separator, as a name may contain one' {
        Get-QueryListItemDoId -Content "A - B - 77" | Should -Be "77"
    }

    It 'Should return nothing for <Case>' -ForEach @(
        @{ Case = 'no separator'; Content = "Accounts" }
        @{ Case = 'a non-numeric suffix'; Content = "Accounts - draft" }
        @{ Case = 'nothing after the separator'; Content = "Accounts - " }
        @{ Case = 'no content'; Content = $null }
    ) {
        Get-QueryListItemDoId -Content $Content | Should -BeNullOrEmpty
    }
}
