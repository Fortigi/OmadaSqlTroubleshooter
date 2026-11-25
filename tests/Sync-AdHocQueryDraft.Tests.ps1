#Requires -Version 7.0
# A tab has a draft exactly when closing it would offer to save it as a new query.

BeforeAll {
    . (Join-Path $PSScriptRoot "AdHocQueryDraftStore.Shared.ps1")
    . (Join-Path $Script:DraftPrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $Script:DraftPrivatePath "Resolve-QuerySavePrompt.ps1")
    . (Join-Path $Script:DraftPrivatePath "Sync-AdHocQueryDraft.ps1")

    function script:New-DraftTab {
        param($DoId = $null, $DraftText = "SELECT 1", $IsDirty = $true, $DisplayName = "Mine", $Id = "tab-1")
        return [PSCustomObject]@{
            Id           = $Id
            DisplayName  = "Query1"
            IsDirty      = $IsDirty
            EditorText   = $DraftText
            DraftText    = $DraftText
            DraftPending = $true
            AppConfig    = [PSCustomObject]@{
                BaseUrl         = "https://tenant.omada.cloud"
                CurrentSqlQuery = [PSCustomObject]@{ DoId = $DoId; DisplayName = $null; FullName = $null }
                Password        = "secret"
            }
            ProposedQueryName = $DisplayName
        }
    }
}

Describe 'Sync-AdHocQueryDraft' -Tag 'Unit' {
    BeforeEach {
        $script:Store = Join-Path $TestDrive ("{0}.json" -f [guid]::NewGuid())
        $script:DraftLog.Clear()
    }

    It 'Should keep an unsaved ad-hoc query' {
        Sync-AdHocQueryDraft -TabSession (New-DraftTab) -Path $script:Store

        $Draft = Get-AdHocQueryDraft -Path $script:Store
        $Draft.TabId | Should -Be "tab-1"
        $Draft.Text | Should -Be "SELECT 1"
        $Draft.TabConfig.BaseUrl | Should -Be "https://tenant.omada.cloud"
        $Draft.TabConfig.DisplayName | Should -Be "Mine"
        $Draft.TabConfig.Password | Should -BeNullOrEmpty
    }

    It 'Should keep what the user typed, not what a programmatic load put on screen' {
        $Tab = New-DraftTab -DraftText "SELECT typed"
        $Tab.EditorText = ""

        Sync-AdHocQueryDraft -TabSession $Tab -Path $script:Store

        (Get-AdHocQueryDraft -Path $script:Store).Text | Should -Be "SELECT typed"
    }

    It 'Should clear the pending flag' {
        $Tab = New-DraftTab

        Sync-AdHocQueryDraft -TabSession $Tab -Path $script:Store

        $Tab.DraftPending | Should -BeFalse
    }

    It 'Should remove the draft when <Case>' -ForEach @(
        @{ Case = 'a saved query is selected'; DoId = 42; Text = "SELECT 1"; Dirty = $true }
        @{ Case = 'the editor was emptied'; DoId = $null; Text = ""; Dirty = $true }
        @{ Case = 'nothing is unsaved'; DoId = $null; Text = "SELECT 1"; Dirty = $false }
    ) {
        Sync-AdHocQueryDraft -TabSession (New-DraftTab) -Path $script:Store
        Sync-AdHocQueryDraft -TabSession (New-DraftTab -Id "tab-2") -Path $script:Store

        Sync-AdHocQueryDraft -TabSession (New-DraftTab -DoId $DoId -DraftText $Text -IsDirty $Dirty) -Path $script:Store

        @(Get-AdHocQueryDraft -Path $script:Store | ForEach-Object { $_.TabId }) | Should -Be @("tab-2")
    }

    It 'Should keep the draft of a disconnected tab' {
        # Not connected is not part of the decision at all - it is the strongest reason to keep it.
        $Tab = New-DraftTab
        $Tab | Add-Member -NotePropertyName ConnectionStatus -NotePropertyValue $false

        Sync-AdHocQueryDraft -TabSession $Tab -Path $script:Store

        @(Get-AdHocQueryDraft -Path $script:Store).Count | Should -Be 1
    }

    It 'Should warn without a dialog, and not throw, when the store cannot be written' {
        Mock Save-AdHocQueryDraft { throw "access denied" }

        { Sync-AdHocQueryDraft -TabSession (New-DraftTab) -Path $script:Store } | Should -Not -Throw

        $script:DraftLog.Count | Should -Be 1
        $script:DraftLog[0].LogType | Should -Be "WARNING"
        $script:DraftLog[0].SkipDialog | Should -BeTrue
        $script:DraftLog[0].Message | Should -Match "access denied"
        $script:DraftLog[0].Message | Should -Match "Query1"
    }

    It 'Should ignore <Case>' -ForEach @(
        @{ Case = 'a missing tab'; Tab = $null }
        @{ Case = 'a tab without an id'; Tab = [PSCustomObject]@{ Id = ""; IsDirty = $true; DraftText = "x" } }
    ) {
        Mock Save-AdHocQueryDraft { }
        Mock Remove-AdHocQueryDraft { }

        Sync-AdHocQueryDraft -TabSession $Tab -Path $script:Store

        Should -Invoke Save-AdHocQueryDraft -Times 0 -Exactly
        Should -Invoke Remove-AdHocQueryDraft -Times 0 -Exactly
    }
}
