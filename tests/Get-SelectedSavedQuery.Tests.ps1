#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-SelectedSavedQuery.ps1")
}

Describe 'Get-SelectedSavedQuery' -Tag 'Unit' {
    It 'Should return the selected query with the name last loaded from the tenant' {
        New-QueryTestState
        $Script:AppConfig.CurrentSqlQuery.DisplayName = "Stale config name"

        $Query = Get-SelectedSavedQuery -Action "rename"

        $Query.DoId | Should -Be "42"
        $Query.DisplayName | Should -Be "Accounts"
    }

    It 'Should fall back to the selection''s own name' {
        New-QueryTestState
        $Script:RunTimeData.CurrentSqlQuery.DisplayName = $null

        (Get-SelectedSavedQuery -Action "rename").DisplayName | Should -Be "Accounts"
    }

    It 'Should refuse while disconnected, naming the action' {
        New-QueryTestState -Connected $false

        Get-SelectedSavedQuery -Action "delete" | Should -BeNullOrEmpty
        $script:QueryLog[0].LogType | Should -Be "WARNING"
        $script:QueryLog[0].Message | Should -Match "Connect to Omada to delete"
    }

    It 'Should refuse an ad-hoc query, naming the action' {
        New-QueryTestState -DoId $null

        Get-SelectedSavedQuery -Action "rename" | Should -BeNullOrEmpty
        $script:QueryLog[0].LogType | Should -Be "WARNING"
        $script:QueryLog[0].Message | Should -Match "Select a saved query to rename"
    }
}
