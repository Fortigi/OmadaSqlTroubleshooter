#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1")
    $script:List = (Get-QmFixture "odata.querylist.json").value
}

Describe 'Select-QueryManagerQuery' -Tag 'Unit' {
    It 'Should keep every query for an empty filter' -ForEach @(@{ Filter = $null }, @{ Filter = "" }, @{ Filter = "  " }) {
        @(Select-QueryManagerQuery -Query $script:List -Filter $Filter).Count | Should -Be 6
    }

    It 'Should find a query by part of its name, ignoring case' {
        @(Select-QueryManagerQuery -Query $script:List -Filter "ORPHAN" | ForEach-Object DisplayName) | Should -Be @("Orphaned accounts")
    }

    It 'Should find a query by its id' {
        @(Select-QueryManagerQuery -Query $script:List -Filter "10544" | ForEach-Object Id) | Should -Be @(10544)
    }

    It 'Should find a query by its technical name' {
        @(Select-QueryManagerQuery -Query $script:List -Filter "SQLTS_Pending" | ForEach-Object Id) | Should -Be @(10577)
    }

    It 'Should honour * and ? as wildcards' {
        @(Select-QueryManagerQuery -Query $script:List -Filter "Identities*manager").Count | Should -Be 1
        @(Select-QueryManagerQuery -Query $script:List -Filter "105?4").Count | Should -Be 1
    }

    It 'Should not search the query text' {
        $Query = [PSCustomObject]@{ Id = 1; DisplayName = "A"; C_QUERY = "SELECT secret" }

        @(Select-QueryManagerQuery -Query @($Query) -Filter "secret").Count | Should -Be 0
    }

    It 'Should find a query by who created it' {
        $Ownership = @{ "10560" = [PSCustomObject]@{ CreatedBy = "CORP\\ann"; ChangedBy = "" } }
        @(Select-QueryManagerQuery -Query $script:List -Filter "corp\\ann" -Ownership $Ownership | ForEach-Object Id) | Should -Be @(10560)
    }

    It 'Should keep only my queries when asked' {
        $Ownership = @{ "10560" = [PSCustomObject]@{ CreatedBy = "ann"; ChangedBy = "bob" }; "10577" = [PSCustomObject]@{ CreatedBy = "bob"; ChangedBy = "ann" } }

        @(Select-QueryManagerQuery -Query $script:List -Ownership $Ownership -UserName "ann" -MyCreated $true | ForEach-Object Id) | Should -Be @(10560)
        @(Select-QueryManagerQuery -Query $script:List -Ownership $Ownership -UserName "ann" -MyUpdated $true | ForEach-Object Id) | Should -Be @(10577)
        @(Select-QueryManagerQuery -Query $script:List -Ownership $Ownership -UserName "ann" -MyCreated $true -MyUpdated $true | ForEach-Object Id) | Should -Be @(10560, 10577)
    }

    It 'Should treat no ownership as none known' {
        @(Select-QueryManagerQuery -Query $script:List -Ownership $null -Filter "").Count | Should -Be 6
    }

    It 'Should keep the original order and drop nulls' {
        @(Select-QueryManagerQuery -Query @($null, $script:List[2], $script:List[0]) -Filter "" | ForEach-Object Id) | Should -Be @(10560, 10521)
    }
}
