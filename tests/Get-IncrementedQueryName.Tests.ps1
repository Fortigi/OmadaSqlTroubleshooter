BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-IncrementedQueryName.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Get-IncrementedQueryName' {
    It 'appends 1 when the base name has no trailing number' {
        Get-IncrementedQueryName -BaseName "Users" | Should -Be "Users1"
    }

    It 'increments the trailing number when the base name already ends in a number' {
        Get-IncrementedQueryName -BaseName "MyQuery1" | Should -Be "MyQuery2"
    }

    It 'increments a trailing number that follows a space' {
        Get-IncrementedQueryName -BaseName "Report 3" | Should -Be "Report 4"
    }

    It 'bumps past names that are already taken' {
        Get-IncrementedQueryName -BaseName "Users" -ExistingNames @("Users1", "Users2") | Should -Be "Users3"
    }

    It 'skips only the taken names, not a whole range' {
        Get-IncrementedQueryName -BaseName "Users" -ExistingNames @("Users1", "Users3") | Should -Be "Users2"
    }

    It 'preserves the zero-padding width of the trailing number' {
        Get-IncrementedQueryName -BaseName "Query09" | Should -Be "Query10"
    }

    It 'preserves a wider zero-padding width' {
        Get-IncrementedQueryName -BaseName "Query008" | Should -Be "Query009"
    }

    It 'increments only the last run of digits' {
        Get-IncrementedQueryName -BaseName "v12ab34" | Should -Be "v12ab35"
    }

    It 'falls back to the Query{#} scheme when the base name is blank' {
        Get-IncrementedQueryName -BaseName "" | Should -Be "Query1"
    }

    It 'falls back to the Query{#} scheme when the base name is whitespace' {
        Get-IncrementedQueryName -BaseName "   " -ExistingNames @("Query1") | Should -Be "Query2"
    }

    It 'trims surrounding whitespace on the base name before matching' {
        Get-IncrementedQueryName -BaseName "  Report 3  " | Should -Be "Report 4"
    }

    It 'matches existing names case-insensitively and trims them' {
        Get-IncrementedQueryName -BaseName "Users" -ExistingNames @(" users1 ") | Should -Be "Users2"
    }
}
