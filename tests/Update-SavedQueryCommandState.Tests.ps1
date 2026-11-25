#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Update-SavedQueryCommandState.ps1")
}

Describe 'Update-SavedQueryCommandState' -Tag 'Unit' {
    It 'Should enable Rename, Delete and Open in Omada for a selected saved query on a connected tab' {
        New-QueryTestState

        Update-SavedQueryCommandState

        $Script:MainForm.Elements.ButtonRenameQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonDeleteQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonOpenQueryInOmada.IsEnabled | Should -BeTrue
    }

    It 'Should disable them when <Case>' -ForEach @(
        @{ Case = 'disconnected'; DoId = 42; Connected = $false; Selected = $true }
        @{ Case = 'the query is ad-hoc'; DoId = $null; Connected = $true; Selected = $true }
        @{ Case = 'nothing is selected'; DoId = 42; Connected = $true; Selected = $false }
    ) {
        New-QueryTestState -DoId $DoId -Connected $Connected
        $Script:MainForm.Elements.ButtonRenameQuery.IsEnabled = $true
        $Script:MainForm.Elements.ButtonDeleteQuery.IsEnabled = $true
        $Script:MainForm.Elements.ButtonOpenQueryInOmada.IsEnabled = $true
        if (-not $Selected) { $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $null }

        Update-SavedQueryCommandState

        $Script:MainForm.Elements.ButtonRenameQuery.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.ButtonDeleteQuery.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.ButtonOpenQueryInOmada.IsEnabled | Should -BeFalse
    }

    It 'Should tolerate a tab without the buttons' {
        New-QueryTestState
        $Script:MainForm.Elements = [PSCustomObject]@{ ComboBoxSelectQuery = [PSCustomObject]@{ SelectedItem = "x" } }

        { Update-SavedQueryCommandState } | Should -Not -Throw
    }
}
