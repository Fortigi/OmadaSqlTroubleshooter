#Requires -Version 7.0
BeforeAll { . ([System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private", "Resolve-EditorLoadText.ps1")) }

Describe 'Resolve-EditorLoadText' -Tag 'Unit' {
    It 'Should load the saved text normally' {
        $Load = Resolve-EditorLoadText -TabSession ([PSCustomObject]@{ Id = "a" }) -SavedText "SELECT saved"

        $Load.Text | Should -Be "SELECT saved"
        $Load.Restored | Should -BeFalse
    }

    It 'Should load a version waiting to be restored instead, once' {
        $Tab = [PSCustomObject]@{ Id = "a"; PendingRestoreText = "SELECT old" }

        $First = Resolve-EditorLoadText -TabSession $Tab -SavedText "SELECT saved"
        $Second = Resolve-EditorLoadText -TabSession $Tab -SavedText "SELECT saved"

        $First.Text | Should -Be "SELECT old"
        $First.Restored | Should -BeTrue
        $Second.Text | Should -Be "SELECT saved"
        $Second.Restored | Should -BeFalse
    }

    It 'Should restore an empty older version as empty' {
        (Resolve-EditorLoadText -TabSession ([PSCustomObject]@{ PendingRestoreText = "" }) -SavedText "SELECT saved").Text | Should -Be ""
    }

    It 'Should load the saved text without a tab' {
        (Resolve-EditorLoadText -TabSession $null -SavedText "SELECT saved").Restored | Should -BeFalse
    }

    It 'Should load the saved text for a tab that never had a version waiting' {
        $Load = Resolve-EditorLoadText -TabSession ([PSCustomObject]@{ Id = "a"; PendingRestoreText = $null }) -SavedText "SELECT saved"

        $Load.Text | Should -Be "SELECT saved"
        $Load.Restored | Should -BeFalse
    }
}
