#Requires -Version 7.0
# The one decision behind both close prompts (one tab, and the whole application) and the draft cache.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $PrivatePath "Resolve-QuerySavePrompt.ps1")
}

Describe 'Resolve-QuerySavePrompt' -Tag 'Unit' {
    It 'Should offer to save changes to a selected query' {
        Resolve-QuerySavePrompt -QueryDoId 42 -EditorText "SELECT 1" -IsDirty $true -Connected $true | Should -Be "SaveExisting"
    }

    It 'Should offer to save an ad-hoc query as a new query' {
        Resolve-QuerySavePrompt -QueryDoId $null -EditorText "SELECT 1" -IsDirty $true -Connected $true | Should -Be "SaveNew"
    }

    It 'Should treat DoId 0 as ad-hoc, as a reset leaves it' {
        Resolve-QuerySavePrompt -QueryDoId 0 -EditorText "SELECT 1" -IsDirty $true -Connected $true | Should -Be "SaveNew"
    }

    It 'Should not offer anything when nothing changed' -ForEach @(
        @{ DoId = 42 }
        @{ DoId = $null }
    ) {
        Resolve-QuerySavePrompt -QueryDoId $DoId -EditorText "SELECT 1" -IsDirty $false -Connected $true | Should -Be "None"
    }

    It 'Should not offer to save an empty editor (<Case>)' -ForEach @(
        @{ Case = 'no text known'; Text = $null; DoId = $null }
        @{ Case = 'empty'; Text = ''; DoId = $null }
        @{ Case = 'only blanks and line breaks'; Text = "  `r`n`t "; DoId = $null }
        @{ Case = 'a selected query emptied'; Text = ''; DoId = 42 }
    ) {
        Resolve-QuerySavePrompt -QueryDoId $DoId -EditorText $Text -IsDirty $true -Connected $true | Should -Be "None"
    }

    It 'Should report that a disconnected tab cannot save (<Case>)' -ForEach @(
        @{ Case = 'selected query'; DoId = 42 }
        @{ Case = 'ad-hoc query'; DoId = $null }
    ) {
        Resolve-QuerySavePrompt -QueryDoId $DoId -EditorText "SELECT 1" -IsDirty $true -Connected $false | Should -Be "Unavailable"
    }

    It 'Should not report a disconnected tab with nothing to save' {
        Resolve-QuerySavePrompt -QueryDoId 42 -EditorText "" -IsDirty $true -Connected $false | Should -Be "None"
        Resolve-QuerySavePrompt -QueryDoId 42 -EditorText "SELECT 1" -IsDirty $false -Connected $false | Should -Be "None"
    }
}
