#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Get-TabEditorText.ps1"))
}

Describe 'Get-TabEditorText' -Tag 'Unit' {
    It 'Should return what the editor reported' {
        Get-TabEditorText -TabSession ([PSCustomObject]@{ EditorText = "SELECT 1"; PendingEditorText = "SELECT 2" }) | Should -Be "SELECT 1"
    }

    It 'Should return an empty report as empty, not fall back' {
        Get-TabEditorText -TabSession ([PSCustomObject]@{ EditorText = ""; PendingEditorText = "SELECT 2" }) | Should -Be ""
    }

    It 'Should fall back to the text waiting to be pushed into an editor that has not loaded' {
        Get-TabEditorText -TabSession ([PSCustomObject]@{ EditorText = $null; PendingEditorText = "SELECT 2" }) | Should -Be "SELECT 2"
    }

    It 'Should return nothing for <Case>' -ForEach @(
        @{ Case = 'a missing tab'; Tab = $null }
        @{ Case = 'a tab that knows no text'; Tab = [PSCustomObject]@{ Id = "a" } }
    ) {
        Get-TabEditorText -TabSession $Tab | Should -BeNullOrEmpty
    }
}
