#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1") }

Describe 'Get-QueryManagerColumn' -Tag 'Unit' {
    It 'Should put Id, DisplayName and Name first and the other fields alphabetically after them' {
        $Query = [PSCustomObject]@{ Zeta = 1; Name = "n"; Alpha = 2; DisplayName = "d"; Id = 1 }

        @(Get-QueryManagerColumn -Query @($Query)) | Should -Be @("Id", "DisplayName", "Name", "Alpha", "Zeta")
    }

    It 'Should leave out annotations, the query text and Deleted' {
        $Query = [PSCustomObject]@{ "@odata.etag" = "x"; Id = 1; C_QUERY = "SELECT"; Deleted = $false; Extra = 1 }

        @(Get-QueryManagerColumn -Query @($Query)) | Should -Be @("Id", "Extra")
    }

    It 'Should show a field that only some queries have' {
        @(Get-QueryManagerColumn -Query @([PSCustomObject]@{ Id = 1 }, [PSCustomObject]@{ Id = 2; UId = "u" })) | Should -Be @("Id", "UId")
    }

    It 'Should cover the fields the recorded query list has' {
        @(Get-QueryManagerColumn -Query (Get-QmFixture "odata.querylist.json").value) | Should -Be @("Id", "DisplayName", "Name")
    }

    It 'Should return no columns for no queries' {
        @(Get-QueryManagerColumn -Query @($null)).Count | Should -Be 0
    }
}
