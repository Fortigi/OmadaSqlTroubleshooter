#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'ConvertTo-QueryHistoryEntry' -Tag 'Unit' {
    It 'Should read the recorded history, newest first' {
        $Entry = @(ConvertTo-QueryHistoryEntry -Row (Get-QmFixture "asmx.paging.history.json").d.Rows)

        $Entry.Count | Should -Be 2
        $Entry[0].What | Should -Be "Modify"
        $Entry[0].When | Should -Be ([DateTime]::new(2026, 6, 30, 20, 41, 0))
        $Entry[0].Who | Should -Be "System (SYSTEM)"
        $Entry[0].Fields | Should -Be "SQL Query"
        $Entry[1].What | Should -Be "Create"
    }

    It 'Should list every changed field, not only the SQL text' {
        $Row = [PSCustomObject]@{ Who = "me"; What = "Modify"; When = "2026-01-02T03:04:05"; ChangedFields = '[{"Field":"Name","OldValue":"a","NewValue":"b"},{"Field":"SQL Query"}]' }

        (ConvertTo-QueryHistoryEntry -Row @($Row)).Fields | Should -Be "Name, SQL Query"
    }

    It 'Should keep a change whose fields cannot be read' {
        $Row = [PSCustomObject]@{ Who = "me"; What = "Modify"; When = "2026-01-02T03:04:05"; ChangedFields = "not json" }

        $Entry = ConvertTo-QueryHistoryEntry -Row @($Row)
        $Entry.Who | Should -Be "me"
        $Entry.Fields | Should -Be ""
    }

    It 'Should sort a change without a readable date last' {
        $Rows = @(
            [PSCustomObject]@{ Who = "undated"; What = "Modify"; When = "not a date"; ChangedFields = "[]" }
            [PSCustomObject]@{ Who = "dated"; What = "Modify"; When = "2020-01-01T00:00:00"; ChangedFields = "[]" }
        )

        @(ConvertTo-QueryHistoryEntry -Row $Rows | ForEach-Object Who) | Should -Be @("dated", "undated")
    }

    It 'Should return nothing for no rows' {
        @(ConvertTo-QueryHistoryEntry -Row @($null)).Count | Should -Be 0
    }
}
