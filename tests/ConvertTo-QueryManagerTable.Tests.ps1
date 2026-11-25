#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'ConvertTo-QueryManagerTable' -Tag 'Unit' {
    It 'Should hold one row per query, in order, under the shown columns' {
        $Table = ConvertTo-QueryManagerTable -Query (Get-QmFixture "odata.querylist.json").value

        $Table.GetType().FullName | Should -Be "System.Data.DataTable"
        $Table.Rows.Count | Should -Be 6
        @($Table.Columns | ForEach-Object ColumnName) | Should -Be @("Id", "DisplayName", "Name")
        $Table.Rows[0]["DisplayName"] | Should -Be "Data object overview"
    }

    It 'Should keep the id numeric so it sorts as a number' {
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = 10544 }, [PSCustomObject]@{ Id = 9001 })

        $Table.Columns["Id"].DataType | Should -Be ([long])
        $View = $Table.DefaultView
        $View.Sort = "Id ASC"
        $View[0]["Id"] | Should -Be 9001
    }

    It 'Should show a reference as text and a missing id as no value' {
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = $null; Connection = [PSCustomObject]@{ Id = 3; DisplayName = "OISES" } })

        $Table.Rows[0]["Connection"] | Should -Be "OISES - 3"
        $Table.Rows[0]["Id"] | Should -BeOfType [System.DBNull]
    }

    It 'Should return an empty table, not nothing, for no queries' {
        $Table = ConvertTo-QueryManagerTable -Query @()

        $Table.GetType().FullName | Should -Be "System.Data.DataTable"
        $Table.Rows.Count | Should -Be 0
    }
}

Describe 'ConvertTo-QueryManagerCell' -Tag 'Unit' {
    It 'Should hold the id as a number' {
        ConvertTo-QueryManagerCell -Name "Id" -Value "42" | Should -BeOfType [long]
    }

    It 'Should hold anything else as its shown text' {
        ConvertTo-QueryManagerCell -Name "Name" -Value 42 | Should -BeExactly "42"
    }
}
