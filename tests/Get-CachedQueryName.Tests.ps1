#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Get-CachedQueryName.ps1"))
}

Describe 'Get-CachedQueryName' -Tag 'Unit' {
    It 'Should flatten the cached list into its names, in order' {
        @(Get-CachedQueryName -QueryList @(@{ 1 = "First" }, @{ 2 = "Second" })) | Should -Be @("First", "Second")
    }

    It 'Should skip blank names and entries of another shape' {
        @(Get-CachedQueryName -QueryList @(@{ 1 = "" }, "not a hashtable", $null, @{ 2 = "Kept" })) | Should -Be @("Kept")
    }

    It 'Should return nothing for no list' {
        @(Get-CachedQueryName -QueryList $null).Count | Should -Be 0
    }
}
