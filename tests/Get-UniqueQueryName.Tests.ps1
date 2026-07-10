BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-UniqueQueryName.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Get-UniqueQueryName' {
    It 'returns Query{StartNumber} when nothing collides' {
        Get-UniqueQueryName -ExistingNames @() -StartNumber 7 | Should -Be "Query7"
    }

    It 'defaults StartNumber to 1' {
        Get-UniqueQueryName | Should -Be "Query1"
    }

    It 'treats a StartNumber below 1 as 1' {
        Get-UniqueQueryName -ExistingNames @() -StartNumber 0 | Should -Be "Query1"
    }

    It 'bumps # until the name is unique against the existing query list' {
        Get-UniqueQueryName -ExistingNames @("Query7", "Query8") -StartNumber 7 | Should -Be "Query9"
    }

    It 'skips only the taken names, not a whole range' {
        Get-UniqueQueryName -ExistingNames @("Query7", "Query9") -StartNumber 7 | Should -Be "Query8"
    }

    It 'ignores empty/whitespace entries and trims names when matching' {
        Get-UniqueQueryName -ExistingNames @("", "  ", " Query7 ") -StartNumber 7 | Should -Be "Query8"
    }

    It 'does not treat unrelated query names as collisions' {
        Get-UniqueQueryName -ExistingNames @("MyReport", "Users - c-13") -StartNumber 7 | Should -Be "Query7"
    }
}
