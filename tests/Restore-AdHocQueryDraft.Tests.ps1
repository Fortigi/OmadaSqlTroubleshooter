#Requires -Version 7.0
# At start-up: offer the drafts back, at the user's request.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Resolve-AdHocQueryDraftRestore.ps1")
    . (Join-Path $PrivatePath "ConvertTo-AdHocQueryDraftTabConfig.ps1")
    . (Join-Path $PrivatePath "Restore-AdHocQueryDraft.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType = "INFO", $ErrorObject, [switch]$SkipDialog) process { } }
    function Get-AdHocQueryDraft { }
    function Remove-AdHocQueryDraft { param([string]$TabId, [switch]$All) }
    function Open-ChoiceForm { param($Title, $Message, $LeftButtonText, $RightButtonText) }
    function Set-AdHocQueryDraftOnTab { param($TabSession, $Draft) }
    function New-TabSession { param($RestoreFrom, [switch]$Deferred) }
    function Get-ActiveTabSession { }
    function Get-TabControlSessions { }
    function Set-ActiveTabContext { param($TabSession) }

    $script:Drafts = @(
        [PSCustomObject]@{ TabId = "restored"; Text = "SELECT 1"; TabConfig = [PSCustomObject]@{ Id = "restored" } }
        [PSCustomObject]@{ TabId = "crashed"; Text = "SELECT 2"; TabConfig = [PSCustomObject]@{ Id = "crashed"; BaseUrl = "https://t" } }
    )
}

Describe 'Restore-AdHocQueryDraft' -Tag 'Unit' {
    BeforeEach {
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test"; ResetRequested = $false }
        $script:Active = [PSCustomObject]@{ Id = "restored"; TabItem = "item-restored" }
        $Script:Tabs = @($script:Active)
        $script:TabControl = [PSCustomObject]@{ SelectedItem = $null }

        Mock Get-AdHocQueryDraft { $script:Drafts }
        Mock Remove-AdHocQueryDraft { }
        Mock Set-AdHocQueryDraftOnTab { }
        Mock New-TabSession { [PSCustomObject]@{ Id = $RestoreFrom.Id; TabItem = "item-new" } }
        Mock Get-ActiveTabSession { $script:Active }
        Mock Get-TabControlSessions { $script:TabControl }
        Mock Set-ActiveTabContext { }
    }

    It 'Should discard the drafts without asking when a reset was requested' {
        $Script:RunTimeConfig.ResetRequested = $true
        Mock Open-ChoiceForm { $true }

        Restore-AdHocQueryDraft

        Should -Invoke Remove-AdHocQueryDraft -Times 1 -Exactly -ParameterFilter { $All }
        Should -Invoke Open-ChoiceForm -Times 0 -Exactly
        Should -Invoke Set-AdHocQueryDraftOnTab -Times 0 -Exactly
    }

    It 'Should not ask when there are no drafts' {
        Mock Get-AdHocQueryDraft { }
        Mock Open-ChoiceForm { $true }

        Restore-AdHocQueryDraft

        Should -Invoke Open-ChoiceForm -Times 0 -Exactly
    }

    It 'Should ask, naming how many drafts there are' {
        Mock Open-ChoiceForm { $null }

        Restore-AdHocQueryDraft

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Message -match '^2 ad-hoc' -and $LeftButtonText -eq "Restore" -and $RightButtonText -eq "Discard" }
    }

    It 'Should delete every draft when the user discards them' {
        Mock Open-ChoiceForm { $false }

        Restore-AdHocQueryDraft

        Should -Invoke Remove-AdHocQueryDraft -Times 1 -Exactly -ParameterFilter { $All }
        Should -Invoke Set-AdHocQueryDraftOnTab -Times 0 -Exactly
    }

    It 'Should keep the drafts for next time when the dialog is closed without an answer' {
        Mock Open-ChoiceForm { $null }

        Restore-AdHocQueryDraft

        Should -Invoke Remove-AdHocQueryDraft -Times 0 -Exactly
        Should -Invoke Set-AdHocQueryDraftOnTab -Times 0 -Exactly
        Should -Invoke New-TabSession -Times 0 -Exactly
    }

    It 'Should put a draft back into its restored tab, and open a deferred tab for the other' {
        Mock Open-ChoiceForm { $true }

        Restore-AdHocQueryDraft

        Should -Invoke Set-AdHocQueryDraftOnTab -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "restored" -and $Draft.Text -eq "SELECT 1" }
        Should -Invoke New-TabSession -Times 1 -Exactly -ParameterFilter { $Deferred -and $RestoreFrom.Id -eq "crashed" -and $RestoreFrom.BaseUrl -eq "https://t" }
        Should -Invoke Set-AdHocQueryDraftOnTab -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "crashed" -and $Draft.Text -eq "SELECT 2" }
        Should -Invoke Remove-AdHocQueryDraft -Times 0 -Exactly
    }

    It 'Should leave the tab that was active selected after opening new ones' {
        Mock Open-ChoiceForm { $true }

        Restore-AdHocQueryDraft

        $script:TabControl.SelectedItem | Should -Be "item-restored"
        Should -Invoke Set-ActiveTabContext -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "restored" }
        $Script:SuppressEditorSync | Should -BeFalse
    }

    It 'Should open a tab from the tab id alone when a draft carries no settings' {
        $script:Drafts[1].TabConfig = $null
        try {
            Mock Open-ChoiceForm { $true }

            Restore-AdHocQueryDraft

            Should -Invoke New-TabSession -Times 1 -Exactly -ParameterFilter { $RestoreFrom.Id -eq "crashed" -and $null -eq $RestoreFrom.Password }
        }
        finally {
            $script:Drafts[1].TabConfig = [PSCustomObject]@{ Id = "crashed"; BaseUrl = "https://t" }
        }
    }

    It 'Should keep a draft it could not open a tab for' {
        Mock Open-ChoiceForm { $true }
        Mock New-TabSession { $null }

        Restore-AdHocQueryDraft

        Should -Invoke Set-AdHocQueryDraftOnTab -Times 1 -Exactly
        Should -Invoke Remove-AdHocQueryDraft -Times 0 -Exactly
    }

    It 'Should not throw when restoring fails' {
        Mock Open-ChoiceForm { throw "boom" }

        { Restore-AdHocQueryDraft } | Should -Not -Throw
    }
}
