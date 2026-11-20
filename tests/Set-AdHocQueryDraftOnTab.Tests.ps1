#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Set-TabEditorText.ps1")
    . (Join-Path $PrivatePath "Set-AdHocQueryDraftOnTab.ps1")

    $script:Headers = 0
    function Update-TabHeaderTitle { param($TabSession) $script:Headers++ }

    function script:New-RestoredTab {
        return [PSCustomObject]@{
            Id                 = "tab-1"
            IsDirty            = $false
            PendingEditorText  = $null
            PendingDisplayName = $null
            Elements           = [PSCustomObject]@{ TextBoxDisplayName = [PSCustomObject]@{ Text = $null } }
        }
    }
}

Describe 'Set-AdHocQueryDraftOnTab' -Tag 'Unit' {
    BeforeEach {
        $script:Headers = 0
    }

    It 'Should queue the text for the editor and record it as unsaved work' {
        $Tab = New-RestoredTab

        Set-AdHocQueryDraftOnTab -TabSession $Tab -Draft ([PSCustomObject]@{ TabId = "tab-1"; Text = "SELECT 1"; TabConfig = $null })

        $Tab.PendingEditorText | Should -Be "SELECT 1"
        $Tab.EditorText | Should -Be "SELECT 1"
        $Tab.DraftText | Should -Be "SELECT 1"
        $Tab.IsDirty | Should -BeTrue
        $script:Headers | Should -Be 1
    }

    It 'Should restore the Display name the draft was kept with' {
        $Tab = New-RestoredTab

        Set-AdHocQueryDraftOnTab -TabSession $Tab -Draft ([PSCustomObject]@{ Text = "SELECT 1"; TabConfig = [PSCustomObject]@{ DisplayName = "Mine" } })

        $Tab.PendingDisplayName | Should -Be "Mine"
        $Tab.Elements.TextBoxDisplayName.Text | Should -Be "Mine"
    }

    It 'Should leave the Display name alone when the draft has none' {
        $Tab = New-RestoredTab
        $Tab.Elements.TextBoxDisplayName.Text = "Existing"

        Set-AdHocQueryDraftOnTab -TabSession $Tab -Draft ([PSCustomObject]@{ Text = "SELECT 1"; TabConfig = [PSCustomObject]@{ DisplayName = " " } })

        $Tab.PendingDisplayName | Should -BeNullOrEmpty
        $Tab.Elements.TextBoxDisplayName.Text | Should -Be "Existing"
    }
}
