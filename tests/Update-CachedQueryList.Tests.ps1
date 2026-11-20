#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Update-CachedQueryList.ps1"))
}

Describe 'Update-CachedQueryList' -Tag 'Unit' {
    It 'Should rename the matching entry and keep its key and position' {
        $Result = @(Update-CachedQueryList -QueryList @(@{ 1 = "A" }, @{ 2 = "B" }, @{ 3 = "C" }) -DoId "2" -DisplayName "Renamed")

        $Result.Count | Should -Be 3
        $Result[1][2] | Should -Be "Renamed" -Because "the key keeps its original (numeric) type"
        $Result[0][1] | Should -Be "A"
        $Result[2][3] | Should -Be "C"
    }

    It 'Should remove the matching entry' {
        $Result = @(Update-CachedQueryList -QueryList @(@{ 1 = "A" }, @{ 2 = "B" }) -DoId "1" -Remove)

        $Result.Count | Should -Be 1
        $Result[0][2] | Should -Be "B"
    }

    It 'Should leave a list without the query unchanged' {
        $Result = @(Update-CachedQueryList -QueryList @(@{ 1 = "A" }) -DoId "9" -DisplayName "X")

        $Result.Count | Should -Be 1
        $Result[0][1] | Should -Be "A"
    }

    It 'Should pass other entries through and drop nulls' {
        $Result = @(Update-CachedQueryList -QueryList @($null, "odd", @{ 1 = "A" }) -DoId "1" -Remove)

        @($Result) | Should -Be @("odd")
    }

    It 'Should return nothing for no list' {
        @(Update-CachedQueryList -QueryList $null -DoId "1" -Remove).Count | Should -Be 0
    }
}
