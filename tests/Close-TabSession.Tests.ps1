#Requires -Version 7.0
# Closing one tab: the save prompt follows Resolve-QuerySavePrompt, the teardown only happens after
# the user's answer, and the tab's ad-hoc draft goes with it.

BeforeAll {
    . (Join-Path $PSScriptRoot "CloseFlow.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Close-TabSession.ps1")

    function Request-TabQuerySave { param($TabSession, $Kind, [switch]$ClosingApplication) }
    function Remove-AdHocQueryDraft { param([string]$TabId, [switch]$All) }
    function Complete-TabClose { param($TabToClose, $WasActiveTab, $PreviouslyActiveTab) }

    function script:New-ClosingTab {
        param($Id = "closing", $DoId = 42, $Text = "SELECT 1", [bool]$Dirty = $true, [bool]$Connected = $true)
        return [PSCustomObject]@{
            Id               = $Id
            DisplayName      = $Id
            IsDirty          = $Dirty
            EditorText       = $Text
            ConnectionStatus = $Connected
            AppConfig        = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DoId = $DoId } }
        }
    }
}

Describe 'Close-TabSession' -Tag 'Unit' {
    BeforeEach {
        $script:QueryLog.Clear()
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        $script:Visible = New-ClosingTab -Id "visible" -Dirty $false
        $Script:ActiveTabId = "visible"
        $Script:ConnectionStatus = $true
        Mock Request-TabQuerySave { "Saved" }
        Mock Remove-AdHocQueryDraft { }
        Mock Complete-TabClose { }
        Mock Set-ActiveTabContext { $Script:ActiveTabId = $TabSession.Id; $Script:ConnectionStatus = [bool]$TabSession.ConnectionStatus }
    }

    It 'Should close a clean tab without asking, and forget its draft' {
        $Script:Tabs = @($script:Visible, (New-ClosingTab -Dirty $false))

        Close-TabSession -TabId "closing"

        Should -Invoke Request-TabQuerySave -Times 0 -Exactly
        Should -Invoke Remove-AdHocQueryDraft -Times 1 -Exactly -ParameterFilter { $TabId -eq "closing" }
        Should -Invoke Complete-TabClose -Times 1 -Exactly -ParameterFilter { $TabToClose.Id -eq "closing" -and -not $WasActiveTab -and $PreviouslyActiveTab.Id -eq "visible" }
    }

    It 'Should not offer to save an empty editor' {
        $Script:Tabs = @($script:Visible, (New-ClosingTab -DoId $null -Text " "))

        Close-TabSession -TabId "closing"

        Should -Invoke Request-TabQuerySave -Times 0 -Exactly
        Should -Invoke Complete-TabClose -Times 1 -Exactly
    }

    It 'Should offer to save <Case>' -ForEach @(
        @{ Case = 'changes to a selected query'; DoId = 42; Connected = $true; Expected = "SaveExisting" }
        @{ Case = 'an ad-hoc query as a new one'; DoId = $null; Connected = $true; Expected = "SaveNew" }
        @{ Case = 'nothing, but say a disconnected tab cannot save'; DoId = 42; Connected = $false; Expected = "Unavailable" }
    ) {
        $Script:Tabs = @($script:Visible, (New-ClosingTab -DoId $DoId -Connected $Connected))

        Close-TabSession -TabId "closing"

        Should -Invoke Request-TabQuerySave -Times 1 -Exactly -ParameterFilter { $Kind -eq $Expected -and $TabSession.Id -eq "closing" -and -not $ClosingApplication }
    }

    It 'Should close after the user saved or discarded (<Answer>)' -ForEach @(
        @{ Answer = "Saved" }
        @{ Answer = "Discarded" }
    ) {
        $Script:Tabs = @($script:Visible, (New-ClosingTab))
        Mock Request-TabQuerySave { $Answer }

        Close-TabSession -TabId "closing"

        Should -Invoke Complete-TabClose -Times 1 -Exactly
        Should -Invoke Remove-AdHocQueryDraft -Times 1 -Exactly -ParameterFilter { $TabId -eq "closing" }
    }

    It 'Should keep the tab, its draft and the visible tab when the user cancels' {
        $Script:Tabs = @($script:Visible, (New-ClosingTab -DoId $null))
        Mock Request-TabQuerySave { "Cancel" }

        Close-TabSession -TabId "closing"

        Should -Invoke Complete-TabClose -Times 0 -Exactly
        Should -Invoke Remove-AdHocQueryDraft -Times 0 -Exactly
        $Script:ActiveTabId | Should -Be "visible"
    }

    It 'Should report a closing tab as the active one when it is' {
        $Script:Tabs = @((New-ClosingTab -Dirty $false))
        $Script:ActiveTabId = "closing"

        Close-TabSession -TabId "closing"

        Should -Invoke Complete-TabClose -Times 1 -Exactly -ParameterFilter { $WasActiveTab }
    }

    It 'Should warn about a tab that does not exist' {
        $Script:Tabs = @($script:Visible)

        Close-TabSession -TabId "missing"

        Should -Invoke Complete-TabClose -Times 0 -Exactly
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match "missing"
    }
}
