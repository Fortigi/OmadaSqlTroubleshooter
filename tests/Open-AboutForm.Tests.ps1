#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Open-AboutForm.ps1")
}

Describe 'Get-AboutText' -Tag 'Unit' {
    It 'Should show the version and the copyright up to this year, as the splash screen does' {
        $Text = Get-AboutText -Version "2026.11.25.1" -Year 2026

        $Text.Title | Should -BeExactly "Omada Sql Troubleshooter"
        $Text.Version | Should -BeExactly "Version 2026.11.25.1`nFortigi (C) 2024-2026"
    }

    It 'Should still give a version line without a version' {
        (Get-AboutText -Version "" -Year 2027).Version | Should -BeExactly "Version `nFortigi (C) 2024-2027"
    }
}
