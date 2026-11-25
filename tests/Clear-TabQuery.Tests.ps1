#Requires -Version 7.0
# New: clear the editor for a new ad-hoc query, after offering to save unsaved work.

BeforeAll {
    . (Join-Path $PSScriptRoot "CloseFlow.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Clear-TabSavedQuerySelection.ps1")
    . (Join-Path $Script:QueryPrivatePath "Set-TabEditorText.ps1")
    . (Join-Path $Script:QueryPrivatePath "Clear-TabQuery.ps1")

    function Request-TabQuerySave { param($TabSession, $Kind, [switch]$ClosingApplication, [switch]$NewQuery) }
    function Push-ToEditor { param($ScriptToExecute) }
    function Remove-AdHocQueryDraft { param([string]$TabId, [switch]$All) }
    function Update-SavedQueryCommandState { }
}

Describe 'Clear-TabQuery' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState
        Mock Request-TabQuerySave { "Saved" }
        Mock Push-ToEditor { }
        Mock Remove-AdHocQueryDraft { }
        Mock Update-SavedQueryCommandState { }
        Mock Update-TabHeaderTitle { }
    }

    It 'Should clear a clean tab without asking' {
        Clear-TabQuery

        Should -Invoke Request-TabQuerySave -Times 0 -Exactly
        Should -Invoke Push-ToEditor -Times 1 -Exactly -ParameterFilter { $ScriptToExecute -eq "window.setEditorValue('');" }
    }

    It 'Should turn the tab into an empty, clean ad-hoc query' {
        $script:TestTab.IsDirty = $true
        $script:TestTab.ProposedQueryName = "Old proposal"
        $script:TestTab.DraftText = "SELECT draft"

        Clear-TabQuery

        $Script:AppConfig.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Script:RunTimeData.CurrentSqlQuery.DisplayName | Should -BeNullOrEmpty
        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem | Should -BeNullOrEmpty
        $script:TestTab.IsDirty | Should -BeFalse
        $script:TestTab.EditorText | Should -Be ""
        $script:TestTab.DraftText | Should -BeNullOrEmpty
        $script:TestTab.ProposedQueryName | Should -BeNullOrEmpty
        Should -Invoke Remove-AdHocQueryDraft -Times 1 -Exactly -ParameterFilter { $TabId -eq "tab-1" }
        Should -Invoke Update-SavedQueryCommandState -Times 1 -Exactly
        Should -Invoke Update-TabHeaderTitle -Times 1 -Exactly
    }

    It 'Should offer to save <Case> first, as New' -ForEach @(
        @{ Case = 'changes to a selected query'; DoId = 42; Expected = "SaveExisting" }
        @{ Case = 'an ad-hoc query'; DoId = $null; Expected = "SaveNew" }
    ) {
        New-QueryTestState -DoId $DoId
        $script:TestTab.IsDirty = $true

        Clear-TabQuery

        Should -Invoke Request-TabQuerySave -Times 1 -Exactly -ParameterFilter { $Kind -eq $Expected -and $NewQuery -and -not $ClosingApplication }
    }

    It 'Should not ask about an empty editor' {
        $script:TestTab.IsDirty = $true
        $script:TestTab.EditorText = ""

        Clear-TabQuery

        Should -Invoke Request-TabQuerySave -Times 0 -Exactly
    }

    It 'Should change nothing when the user cancels' {
        $script:TestTab.IsDirty = $true
        Mock Request-TabQuerySave { "Cancel" }

        Clear-TabQuery

        Should -Invoke Push-ToEditor -Times 0 -Exactly
        Should -Invoke Remove-AdHocQueryDraft -Times 0 -Exactly
        $Script:AppConfig.CurrentSqlQuery.DoId | Should -Be 42
        $script:TestTab.IsDirty | Should -BeTrue
    }

    It 'Should clear after the user saved or discarded (<Answer>)' -ForEach @(
        @{ Answer = "Saved" }
        @{ Answer = "Discarded" }
    ) {
        $script:TestTab.IsDirty = $true
        Mock Request-TabQuerySave { $Answer }

        Clear-TabQuery

        Should -Invoke Push-ToEditor -Times 1 -Exactly
    }

    It 'Should do nothing without an active tab' {
        Mock Get-ActiveTabSession { }

        Clear-TabQuery

        Should -Invoke Push-ToEditor -Times 0 -Exactly
    }

    It 'Should never disable a button, so a failed save cannot leave New greyed out' {
        # Regression: the previous New saved under the Display name, disabled itself first, and was
        # never enabled again when the name already existed.
        $Source = Get-Content -Path (Join-Path $Script:QueryPrivatePath "Clear-TabQuery.ps1") -Raw
        $Handler = Get-Content -Path ([System.IO.Path]::Combine((Split-Path $PSScriptRoot -Parent), "src", "Lib", "Events", "MainFormTabContent.Elements.ButtonNewQuery.ps1")) -Raw

        $Source | Should -Not -Match 'IsEnabled\s*=\s*\$false'
        $Handler | Should -Not -Match 'IsEnabled\s*=\s*\$false'
        $Handler | Should -Match 'Clear-TabQuery'
    }
}
