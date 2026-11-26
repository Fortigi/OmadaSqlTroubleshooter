#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'ConvertTo-QueryPropertyList' -Tag 'Unit' {
    BeforeAll {
        $script:Object = Get-QmFixture "odata.queryobject.json"
        $script:Object | Add-Member -NotePropertyName C_SQLTROUBLESHOOTING_DATACONNECTION -NotePropertyValue ([PSCustomObject]@{ Id = 3; DisplayName = "OISES" })
        $script:Entry = @(ConvertTo-QueryHistoryEntry -Row (Get-QmFixture "asmx.paging.history.json").d.Rows)
        function script:Get-Value { param($List) $Value = @{}; $List | ForEach-Object { $Value[$_.Property] = $_.Value }; $Value }
    }

    It 'Should list the query manager''s columns, in their order, under their names' {
        @(ConvertTo-QueryPropertyList -Query $script:Object -HistoryEntry $script:Entry).Property | Should -Be @(Get-QueryManagerColumnDefinition).Header
    }

    It 'Should show the values as the list does' {
        $Value = Get-Value (ConvertTo-QueryPropertyList -Query $script:Object)
        $Value["Id"] | Should -Be "10521"
        $Value["Display name"] | Should -Be "Data object overview"
        $Value["Connection"] | Should -Be "OISES"
        $Value["Is Deleted"] | Should -Be "No"
    }

    It 'Should take created and changed from OData and the view, before the history' {
        $Object = $script:Object.PSObject.Copy()
        $Object | Add-Member -NotePropertyName CreateTime -NotePropertyValue ([datetime]::new(2024, 5, 6, 7, 8, 9)) -Force
        $Ownership = @{ "10521" = [PSCustomObject]@{ CreatedBy = "CORP\\ann"; ChangedBy = "CORP\\bob" } }

        $Value = Get-Value (ConvertTo-QueryPropertyList -Query $Object -Ownership $Ownership -HistoryEntry $script:Entry)

        $Value["Created"] | Should -Be "2024-05-06 07:08:09"
        $Value["Created by"] | Should -Be "CORP\\ann"
        $Value["Changed by"] | Should -Be "CORP\\bob"
    }

    It 'Should fill empty created and changed values from the history' {
        $Value = Get-Value (ConvertTo-QueryPropertyList -Query $script:Object -HistoryEntry $script:Entry)

        $Value["Created"] | Should -Be "2023-07-17 14:33:00"
        $Value["Created by"] | Should -Be "System (SYSTEM)"
        $Value["Changed"] | Should -Be "2026-06-30 20:41:00"
        $Value["Changed by"] | Should -Be "System (SYSTEM)"
    }

    It 'Should still list every property when the object could not be read' {
        $List = @(ConvertTo-QueryPropertyList -Query $null -HistoryEntry $script:Entry)
        $List.Property | Should -Be @(Get-QueryManagerColumnDefinition).Header
        (Get-Value $List)["Created by"] | Should -Be "System (SYSTEM)"
        (Get-Value $List)["Id"] | Should -Be ""
    }
}
