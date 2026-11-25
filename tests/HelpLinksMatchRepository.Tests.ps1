#Requires -Version 7.0
# The Help window's GitHub links against the repository itself: the issue forms they name exist, and
# the bug report's version fields are the ones New-GitHubIssueUrl fills in. Kept out of
# Open-HelpForm.Tests.ps1 because they read .github/, which the mutation-testing sandbox does not copy.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($Script:RepositoryRoot, "src", "Lib", "Functions", "Private", "Open-HelpForm.ps1"))
}

Describe 'Help links and the repository' -Tag 'Unit' {
    It 'Should name issue forms that exist (<Name>)' -ForEach @(@{ Name = "Bug" }, @{ Name = "Feature" }) {
        $Template = ([uri](Get-HelpLink -Name $Name)).Query -replace '^\?template=', ''
        Test-Path -Path ([System.IO.Path]::Combine($Script:RepositoryRoot, ".github", "ISSUE_TEMPLATE", $Template)) | Should -BeTrue
    }
    It 'Should use field ids the bug report form has' {
        $Form = Get-Content -Path ([System.IO.Path]::Combine($Script:RepositoryRoot, ".github", "ISSUE_TEMPLATE", "bug_report.yml")) -Raw
        foreach ($Field in @("module-version", "omadaweb-ps-version", "powershell-version", "os-version")) {
            $Form | Should -Match ("id:\s*{0}\b" -f [regex]::Escape($Field))
        }
    }
}
