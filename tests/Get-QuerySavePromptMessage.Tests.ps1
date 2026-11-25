#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Get-QuerySavePromptMessage.ps1"))
}

Describe 'Get-QuerySavePromptMessage' -Tag 'Unit' {
    It 'Should ask to save changes to a selected query by name' {
        $Message = Get-QuerySavePromptMessage -Kind SaveExisting -Name "Accounts"

        $Message | Should -Match "Save changes to query 'Accounts'"
        $Message | Should -Not -Match "ad-hoc"
    }

    It 'Should say an ad-hoc query is lost when only its tab closes' {
        $Message = Get-QuerySavePromptMessage -Kind SaveNew -Name "Query3"

        $Message | Should -Match "'Query3' is an ad-hoc query"
        $Message | Should -Match "new query"
        $Message | Should -Match "it is lost"
        $Message | Should -Not -Match "next time"
    }

    It 'Should say an ad-hoc query is kept when the application closes' {
        $Message = Get-QuerySavePromptMessage -Kind SaveNew -Name "Query3" -ClosingApplication

        $Message | Should -Match "kept and offered again the next time the application starts"
        $Message | Should -Not -Match "it is lost"
    }

    It 'Should explain that a disconnected tab cannot save' {
        $Message = Get-QuerySavePromptMessage -Kind Unavailable -Name "Accounts"

        $Message | Should -Match "'Accounts'"
        $Message | Should -Match "disconnected"
        $Message | Should -Match "Close it anyway"
    }

    It 'Should refuse a kind it does not know' {
        { Get-QuerySavePromptMessage -Kind None -Name "x" } | Should -Throw
    }

    It 'Should ask before starting a new query instead of before closing (<Kind>)' -ForEach @(
        @{ Kind = "SaveExisting" }
        @{ Kind = "SaveNew" }
    ) {
        $Message = Get-QuerySavePromptMessage -Kind $Kind -Name "Accounts" -NewQuery

        $Message | Should -Match "before starting a new query"
        $Message | Should -Not -Match "before closing"
    }

    It 'Should ask to discard, not close, a disconnected tab''s changes for a new query' {
        $Message = Get-QuerySavePromptMessage -Kind Unavailable -Name "Accounts" -NewQuery

        $Message | Should -Match "Discard them anyway"
        $Message | Should -Not -Match "Close it anyway"
    }
}
