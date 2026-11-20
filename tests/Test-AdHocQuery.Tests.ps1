#Requires -Version 7.0
# An ad-hoc query is SQL with no saved query object behind it. Everything else in this feature -
# executing without pressing New, the save and close prompts, the draft cache - keys off this answer.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Test-AdHocQuery.ps1"))
}

Describe 'Test-AdHocQuery' -Tag 'Unit' {
    It 'Should treat <Case> as an ad-hoc query' -ForEach @(
        @{ Case = 'no DoId'; DoId = $null }
        @{ Case = 'an empty DoId'; DoId = '' }
        @{ Case = 'a blank DoId'; DoId = '   ' }
        @{ Case = 'DoId 0 as a number'; DoId = 0 }
        @{ Case = 'DoId 0 as text'; DoId = '0' }
        @{ Case = 'DoId 0 with blanks around it'; DoId = ' 0 ' }
    ) {
        Test-AdHocQuery -QueryDoId $DoId | Should -BeTrue
    }

    It 'Should treat <Case> as a saved query' -ForEach @(
        @{ Case = 'a numeric DoId'; DoId = 1024 }
        @{ Case = 'a DoId held as text'; DoId = '1024' }
        @{ Case = 'a DoId ending in 0'; DoId = 10 }
        @{ Case = 'DoId 1'; DoId = 1 }
    ) {
        Test-AdHocQuery -QueryDoId $DoId | Should -BeFalse
    }

    It 'Should be callable without any DoId at all' {
        Test-AdHocQuery | Should -BeTrue
    }

    It 'Should answer a [bool]' {
        Test-AdHocQuery -QueryDoId 5 | Should -BeOfType [bool]
    }
}
