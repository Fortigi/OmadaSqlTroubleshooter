#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $PrivatePath "Test-ExecuteQueryInput.ps1")
}

Describe 'Test-ExecuteQueryInput' -Tag 'Unit' {
    It 'Should always allow a saved query, whatever the editor holds' -ForEach @(
        @{ Text = $null }
        @{ Text = '' }
        @{ Text = 'SELECT 1' }
    ) {
        Test-ExecuteQueryInput -QueryDoId 42 -EditorText $Text | Should -BeTrue
    }

    It 'Should allow an ad-hoc query with text' {
        Test-ExecuteQueryInput -QueryDoId $null -EditorText "SELECT 1" | Should -BeTrue
    }

    It 'Should refuse an ad-hoc query with an empty editor (<Case>)' -ForEach @(
        @{ Case = 'unknown'; Text = $null }
        @{ Case = 'empty'; Text = '' }
        @{ Case = 'blank'; Text = " `r`n " }
    ) {
        Test-ExecuteQueryInput -QueryDoId $null -EditorText $Text | Should -BeFalse
    }
}
