#Requires -Version 7.0
# Ad-hoc execution: no saved query selected. It must neither save nor touch a user query object, and
# must run through the temporary object - which the pipeline creates exactly when there is a selection.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $PrivatePath "Resolve-ExecuteQueryScope.ps1")
}

Describe 'Resolve-ExecuteQueryScope' -Tag 'Unit' {
    Context 'Ad-hoc query' {
        It 'Should skip the save' {
            $Scope = Resolve-ExecuteQueryScope -QueryDoId $null -QueryText "SELECT 1"

            $Scope.IsAdHoc | Should -BeTrue
            $Scope.SkipSave | Should -BeTrue
        }

        It 'Should run the whole editor as the selection when nothing is selected' {
            (Resolve-ExecuteQueryScope -QueryDoId $null -QueryText "SELECT 1; SELECT 2").SelectionText | Should -Be "SELECT 1; SELECT 2"
        }

        It 'Should run the selection when there is one' {
            (Resolve-ExecuteQueryScope -QueryDoId $null -QueryText "SELECT 1; SELECT 2" -SelectionText "SELECT 2").SelectionText | Should -Be "SELECT 2"
        }

        It 'Should treat a blank selection as no selection' {
            (Resolve-ExecuteQueryScope -QueryDoId 0 -QueryText "SELECT 1" -SelectionText "   ").SelectionText | Should -Be "SELECT 1"
        }
    }

    Context 'Saved query' {
        It 'Should save as before' {
            $Scope = Resolve-ExecuteQueryScope -QueryDoId 42 -QueryText "SELECT 1"

            $Scope.IsAdHoc | Should -BeFalse
            $Scope.SkipSave | Should -BeFalse
        }

        It 'Should not invent a selection, so a single statement still runs the saved object' {
            (Resolve-ExecuteQueryScope -QueryDoId 42 -QueryText "SELECT 1").SelectionText | Should -BeNullOrEmpty
        }

        It 'Should keep a real selection' {
            (Resolve-ExecuteQueryScope -QueryDoId 42 -QueryText "SELECT 1; SELECT 2" -SelectionText "SELECT 2").SelectionText | Should -Be "SELECT 2"
        }
    }
}
