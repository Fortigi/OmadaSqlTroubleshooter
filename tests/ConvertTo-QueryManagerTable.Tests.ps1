#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'ConvertTo-QueryManagerTable' -Tag 'Unit' {
    It 'Should hold one row per query, in order, under the defined columns and the technical name' {
        $Table = ConvertTo-QueryManagerTable -Query (Get-QmFixture "odata.querylist.json").value

        $Table.GetType().FullName | Should -Be "System.Data.DataTable"
        $Table.Rows.Count | Should -Be 6
        @($Table.Columns | ForEach-Object ColumnName) | Should -Be @(@(Get-QueryManagerColumnDefinition).Name + "Name")
        $Table.Rows[0]["DisplayName"] | Should -Be "Data object overview"
        $Table.Rows[0]["Name"] | Should -Be "SQLTS_DataObjectOverview"
    }

    It 'Should keep the id numeric so it sorts as a number' {
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = 10544 }, [PSCustomObject]@{ Id = 9001 })

        $Table.Columns["Id"].DataType | Should -Be ([long])
        $View = $Table.DefaultView
        $View.Sort = "Id ASC"
        $View[0]["Id"] | Should -Be 9001
    }

    It 'Should fill the columns from OData and the ownership' {
        $Query = [PSCustomObject]@{
            Id = 7; DisplayName = "A"; Deleted = $false; UId = "6a0f"; CreateTime = [datetime]::new(2026, 1, 2, 3, 4, 5)
            C_SQLTROUBLESHOOTING_DATACONNECTION = [PSCustomObject]@{ Id = 3; DisplayName = "OISES" }
        }
        $Table = ConvertTo-QueryManagerTable -Query @($Query) -Ownership @{ "7" = [PSCustomObject]@{ CreatedBy = "ann"; ChangedBy = "bob" } }

        $Row = $Table.Rows[0]
        $Row["Connection"] | Should -Be "OISES"
        $Row["CreateTime"] | Should -Be "2026-01-02 03:04:05"
        $Row["CreatedBy"] | Should -Be "ann"
        $Row["ChangedBy"] | Should -Be "bob"
        $Row["Deleted"] | Should -Be "No"
        $Row["UId"] | Should -Be "6a0f"
        $Row["ChangeTime"] | Should -Be ""
    }

    It 'Should store a missing id as no value' {
        (ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = $null })).Rows[0]["Id"] | Should -BeOfType [System.DBNull]
    }

    It 'Should return an empty table, not nothing, for no queries' {
        $Table = ConvertTo-QueryManagerTable -Query @()

        $Table.GetType().FullName | Should -Be "System.Data.DataTable"
        $Table.Rows.Count | Should -Be 0
    }
}
