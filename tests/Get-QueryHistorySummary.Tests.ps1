#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'Get-QueryHistorySummary' -Tag 'Unit' {
    It 'Should take the creation from the Create entry and the last change from the newest entry' {
        $Entry = @(
            [PSCustomObject]@{ When = [DateTime]"2026-03-01"; Who = "late"; What = "Modify" }
            [PSCustomObject]@{ When = [DateTime]"2024-01-01"; Who = "creator"; What = "Create" }
            [PSCustomObject]@{ When = [DateTime]"2025-01-01"; Who = "middle"; What = "Modify" }
        )

        $Summary = Get-QueryHistorySummary -Entry $Entry
        $Summary.Created | Should -Be ([DateTime]"2024-01-01")
        $Summary.CreatedBy | Should -Be "creator"
        $Summary.Changed | Should -Be ([DateTime]"2026-03-01")
        $Summary.ChangedBy | Should -Be "late"
    }

    It 'Should leave the creation unknown without a Create entry' {
        $Summary = Get-QueryHistorySummary -Entry @([PSCustomObject]@{ When = [DateTime]"2025-01-01"; Who = "x"; What = "Modify" })

        $Summary.Created | Should -BeNullOrEmpty
        $Summary.CreatedBy | Should -BeNullOrEmpty
        $Summary.ChangedBy | Should -Be "x"
    }

    It 'Should ignore entries without a date and leave everything unknown for none' {
        $Summary = Get-QueryHistorySummary -Entry @([PSCustomObject]@{ When = $null; Who = "x"; What = "Create" })

        $Summary.Created | Should -BeNullOrEmpty
        $Summary.Changed | Should -BeNullOrEmpty
    }
}
