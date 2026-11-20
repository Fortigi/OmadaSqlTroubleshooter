#Requires -Version 7.0
# The host's copy of the editor's text. EditorText is what is on screen, DraftText what the user last
# typed - the draft cache persists the latter so a programmatic clear cannot erase a draft.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Set-TabEditorText.ps1"))
}

Describe 'Set-TabEditorText' -Tag 'Unit' {
    It 'Should record a programmatic load as what is on screen only' {
        $Tab = [PSCustomObject]@{ Id = "a"; EditorText = $null; DraftText = "typed"; DraftPending = $false }

        Set-TabEditorText -TabSession $Tab -Text "loaded"

        $Tab.EditorText | Should -Be "loaded"
        $Tab.DraftText | Should -Be "typed"
        $Tab.DraftPending | Should -BeFalse
    }

    It 'Should record a user edit as the draft too, and queue it for the cache' {
        $Tab = [PSCustomObject]@{ Id = "a"; EditorText = $null; DraftText = $null; DraftPending = $false }

        Set-TabEditorText -TabSession $Tab -Text "SELECT 1" -UserEdit

        $Tab.EditorText | Should -Be "SELECT 1"
        $Tab.DraftText | Should -Be "SELECT 1"
        $Tab.DraftPending | Should -BeTrue
    }

    It 'Should keep a programmatic clear from touching the draft' {
        $Tab = [PSCustomObject]@{ Id = "a"; EditorText = $null; DraftText = $null; DraftPending = $false }
        Set-TabEditorText -TabSession $Tab -Text "SELECT 1" -UserEdit

        Set-TabEditorText -TabSession $Tab -Text ""

        $Tab.EditorText | Should -Be ""
        $Tab.DraftText | Should -Be "SELECT 1"
    }

    It 'Should add the properties to a tab object that does not have them' {
        $Tab = [PSCustomObject]@{ Id = "a" }

        Set-TabEditorText -TabSession $Tab -Text "x" -UserEdit

        $Tab.EditorText | Should -Be "x"
        $Tab.DraftText | Should -Be "x"
        $Tab.DraftPending | Should -BeTrue
    }

    It 'Should ignore a missing tab' {
        { Set-TabEditorText -TabSession $null -Text "x" } | Should -Not -Throw
    }
}
