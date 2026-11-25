#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Resolve-MainMenuItemState.ps1")
}

Describe 'Resolve-MainMenuItemState' -Tag 'Unit' {
    BeforeEach {
        $Elements = @{
            ButtonSaveQuery           = [PSCustomObject]@{ IsEnabled = $true }
            ButtonDeleteQuery         = [PSCustomObject]@{ IsEnabled = $false }
            ButtonConnect             = [PSCustomObject]@{ IsEnabled = $true }
            ButtonConnectText         = [PSCustomObject]@{ Text = "_Disconnect" }
            ButtonExecuteQuery        = [PSCustomObject]@{ IsEnabled = $true }
            ButtonExecuteQueryText    = [PSCustomObject]@{ Text = "_Cancel" }
            ButtonSaveQueryText       = [PSCustomObject]@{ Text = "Save" }
            CheckboxMyCreatedQueries  = [PSCustomObject]@{ IsEnabled = $true; IsChecked = $true }
            CheckboxMyUpdatedQueries  = [PSCustomObject]@{ IsEnabled = $false; IsChecked = $false }
        }
    }

    It 'Should mirror the toolbar button''s enabled state (<Name>)' -ForEach @(
        @{ Name = "ButtonSaveQuery"; Expected = $true }
        @{ Name = "ButtonDeleteQuery"; Expected = $false }
        @{ Name = "ButtonMissing"; Expected = $false }
    ) {
        $State = Resolve-MainMenuItemState -Tag "Button:$Name" -Elements $Elements
        $State.IsEnabled | Should -Be $Expected
        $State.IsChecked | Should -BeNullOrEmpty
        $State.Header | Should -BeNullOrEmpty
    }

    It 'Should take the current text of <Name>' -ForEach @(
        @{ Name = "ButtonConnect"; Expected = "_Disconnect" }
        @{ Name = "ButtonExecuteQuery"; Expected = "_Cancel" }
    ) {
        (Resolve-MainMenuItemState -Tag "Button:$Name" -Elements $Elements).Header | Should -BeExactly $Expected
    }

    It 'Should disable every tab-bound item without a tab (<Tag>)' -ForEach @(
        @{ Tag = "Button:ButtonSaveQuery" }
        @{ Tag = "Button:ButtonConnect" }
        @{ Tag = "Check:CheckboxMyCreatedQueries" }
        @{ Tag = "Action:ResultsToGrid" }
        @{ Tag = "Tab:Close" }
    ) {
        $State = Resolve-MainMenuItemState -Tag $Tag -Elements $null
        $State.IsEnabled | Should -BeFalse
        $State.Header | Should -BeNullOrEmpty
    }

    It 'Should mirror the filter checkbox (<Name>)' -ForEach @(
        @{ Name = "CheckboxMyCreatedQueries"; Enabled = $true; Checked = $true }
        @{ Name = "CheckboxMyUpdatedQueries"; Enabled = $false; Checked = $false }
    ) {
        $State = Resolve-MainMenuItemState -Tag "Check:$Name" -Elements $Elements
        $State.IsEnabled | Should -Be $Enabled
        $State.IsChecked | Should -Be $Checked
    }

    It 'Should report a filter as unchecked without a tab' {
        (Resolve-MainMenuItemState -Tag "Check:CheckboxMyCreatedQueries" -Elements $null).IsChecked | Should -BeFalse
    }

    It 'Should follow the result context menu (<Name>), the Copy as items through their submenu' -ForEach @(
        @{ Name = "Copy"; Expected = $true }
        @{ Name = "SelectAll"; Expected = $false }
        @{ Name = "CopyAsSqlArray"; Expected = $false }
        @{ Name = "CopyAsPowerShellArray"; Expected = $false }
        @{ Name = "Missing"; Expected = $false }
    ) {
        $Items = @{
            Copy           = [PSCustomObject]@{ IsEnabled = $true }
            SelectAll      = [PSCustomObject]@{ IsEnabled = $false }
            CopyAs         = [PSCustomObject]@{ IsEnabled = $false }
            CopyAsSqlArray = [PSCustomObject]@{ IsEnabled = $true }
            CopyAsPowerShellArray = [PSCustomObject]@{ IsEnabled = $true }
        }
        (Resolve-MainMenuItemState -Tag "Result:$Name" -Elements $Elements -ResultMenuItem $Items).IsEnabled | Should -Be $Expected
    }

    It 'Should enable a Copy as item when its submenu is enabled' {
        $Items = @{ CopyAs = [PSCustomObject]@{ IsEnabled = $true }; CopyAsSqlArray = [PSCustomObject]@{ IsEnabled = $false } }
        (Resolve-MainMenuItemState -Tag "Result:CopyAsSqlArray" -Elements $Elements -ResultMenuItem $Items).IsEnabled | Should -BeTrue
    }

    It 'Should disable result items without context menu items' {
        (Resolve-MainMenuItemState -Tag "Result:Copy" -Elements $Elements -ResultMenuItem $null).IsEnabled | Should -BeFalse
    }

    It 'Should enable a tab command per Test-MainMenuTabActionEnabled' {
        (Resolve-MainMenuItemState -Tag "Tab:Next" -Elements $Elements -TabCount 2).IsEnabled | Should -BeTrue
        (Resolve-MainMenuItemState -Tag "Tab:Next" -Elements $Elements -TabCount 1).IsEnabled | Should -BeFalse
    }

    It 'Should enable an active-tab action with a tab' {
        (Resolve-MainMenuItemState -Tag "Action:ResultsToText" -Elements $Elements).IsEnabled | Should -BeTrue
    }

    It 'Should always enable Exit' {
        (Resolve-MainMenuItemState -Tag "App:Exit" -Elements $null).IsEnabled | Should -BeTrue
    }

    It 'Should disable an item of an unknown kind' {
        (Resolve-MainMenuItemState -Tag "Other:Thing" -Elements $Elements).IsEnabled | Should -BeFalse
    }
}

Describe 'Test-MainMenuTabActionEnabled' -Tag 'Unit' {
    It 'Should answer <Expected> for <Action> with tab <HasTab> and <TabCount> tab(s)' -ForEach @(
        @{ Action = "New"; HasTab = $false; TabCount = 0; Expected = $true }
        @{ Action = "Next"; HasTab = $true; TabCount = 2; Expected = $true }
        @{ Action = "Next"; HasTab = $true; TabCount = 1; Expected = $false }
        @{ Action = "Next"; HasTab = $false; TabCount = 2; Expected = $false }
        @{ Action = "Previous"; HasTab = $true; TabCount = 1; Expected = $false }
        @{ Action = "CloseOthers"; HasTab = $true; TabCount = 1; Expected = $false }
        @{ Action = "CloseOthers"; HasTab = $true; TabCount = 3; Expected = $true }
        @{ Action = "Close"; HasTab = $true; TabCount = 1; Expected = $true }
        @{ Action = "Close"; HasTab = $false; TabCount = 0; Expected = $false }
        @{ Action = "Duplicate"; HasTab = $true; TabCount = 1; Expected = $true }
        @{ Action = "CloseAll"; HasTab = $false; TabCount = 0; Expected = $false }
    ) {
        Test-MainMenuTabActionEnabled -Action $Action -HasTab $HasTab -TabCount $TabCount | Should -Be $Expected
    }
}
