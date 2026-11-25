#Requires -Version 7.0
# Detaching the active tab from its saved query, shared by New and Delete.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Clear-TabSavedQuerySelection.ps1")
}

Describe 'Clear-TabSavedQuerySelection' -Tag 'Unit' {
    It 'Should forget the selected query everywhere the tab keeps it' {
        New-QueryTestState

        Clear-TabSavedQuerySelection -TabSession $script:TestTab

        $Script:AppConfig.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Script:AppConfig.CurrentSqlQuery.FullName | Should -BeNullOrEmpty
        $Script:RunTimeData.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Script:RunTimeData.CurrentSqlQuery.FullName | Should -BeNullOrEmpty
        $Script:RunTimeData.CurrentQueryText | Should -BeNullOrEmpty
        $script:TestTab.AppConfig | Should -Be $Script:AppConfig
        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem | Should -BeNullOrEmpty
        $Script:MainForm.Elements.ComboBoxSelectQuery.Text | Should -Be ""
    }

    It 'Should work without a tab' {
        New-QueryTestState

        { Clear-TabSavedQuerySelection -TabSession $null } | Should -Not -Throw
        $Script:AppConfig.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
    }
}
