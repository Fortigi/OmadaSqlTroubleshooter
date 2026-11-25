#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'ConvertTo-QueryPropertyList' -Tag 'Unit' {
    BeforeAll {
        $script:Object = Get-QmFixture "odata.queryobject.json"
        $script:Object | Add-Member -NotePropertyName C_SQLTROUBLESHOOTING_DATACONNECTION -NotePropertyValue ([PSCustomObject]@{ Id = 3; DisplayName = "OISES" })
        $script:Entry = @(ConvertTo-QueryHistoryEntry -Row (Get-QmFixture "asmx.paging.history.json").d.Rows)
        $script:List = @(ConvertTo-QueryPropertyList -Query $script:Object -HistoryEntry $script:Entry)
        $script:Value = @{}
        $script:List | ForEach-Object { $script:Value[$_.Property] = $_.Value }
    }

    It 'Should list every field OData returned, in its order' {
        @($script:List | Select-Object -First 5 | ForEach-Object Property) | Should -Be @("Id", "Name", "DisplayName", "Deleted", "C_SQLTROUBLESHOOTING_DATACONNECTION")
        $script:Value["Id"] | Should -Be "10521"
        $script:Value["C_SQLTROUBLESHOOTING_DATACONNECTION"] | Should -Be "OISES - 3"
    }

    It 'Should leave out the query text and the OData annotations' {
        $script:Value.ContainsKey("C_QUERY") | Should -BeFalse
        @($script:List | Where-Object { $_.Property -like "@odata*" }).Count | Should -Be 0
    }

    It 'Should add the creation and last change from the history' {
        $script:Value["Created (history)"] | Should -Be "2023-07-17 14:33:00"
        $script:Value["Created by (history)"] | Should -Be "System (SYSTEM)"
        $script:Value["Last changed (history)"] | Should -Be "2026-06-30 20:41:00"
        $script:Value["Last changed by (history)"] | Should -Be "System (SYSTEM)"
    }

    It 'Should still list the history fields when the object could not be read' {
        @(ConvertTo-QueryPropertyList -Query $null -HistoryEntry @() | ForEach-Object Property) | Should -Be @("Created (history)", "Created by (history)", "Last changed (history)", "Last changed by (history)")
    }
}
