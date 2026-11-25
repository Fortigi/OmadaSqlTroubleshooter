#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'ConvertTo-QueryManagerValue' -Tag 'Unit' {
    It 'Should show <Case> as "<Expected>"' -ForEach @(
        @{ Case = 'nothing'; Value = $null; Expected = "" }
        @{ Case = 'text'; Value = "Accounts"; Expected = "Accounts" }
        @{ Case = 'a number'; Value = 10521; Expected = "10521" }
        @{ Case = 'a boolean'; Value = $false; Expected = "False" }
        @{ Case = 'a date, invariantly'; Value = [DateTime]::new(2026, 6, 30, 20, 41, 5); Expected = "2026-06-30 20:41:05" }
        @{ Case = 'a reference by name and id'; Value = [PSCustomObject]@{ Id = 3; DisplayName = "OISES" }; Expected = "OISES - 3" }
        @{ Case = 'a reference without an id'; Value = [PSCustomObject]@{ DisplayName = "OISES" }; Expected = "OISES" }
        @{ Case = 'a reference by id only'; Value = [PSCustomObject]@{ Id = 3 }; Expected = "3" }
        @{ Case = 'a list'; Value = @("a", 2); Expected = "a, 2" }
    ) {
        ConvertTo-QueryManagerValue -Value $Value | Should -BeExactly $Expected
    }

    It 'Should show any other object as compact JSON rather than its type name' {
        ConvertTo-QueryManagerValue -Value ([PSCustomObject]@{ Other = 1 }) | Should -Be '{"Other":1}'
    }
}
