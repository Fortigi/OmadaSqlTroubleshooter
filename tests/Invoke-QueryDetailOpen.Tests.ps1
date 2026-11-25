#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Invoke-QueryDetailOpen.ps1")

    function Open-SqlQueryInActiveTab { param($DoId, $DisplayName) }
    function Open-SqlQueryInTab { param($DoId, $DisplayName) }
    function Request-QueryManagerClose { }
}

Describe 'Invoke-QueryDetailOpen' -Tag 'Unit' {
    BeforeEach {
        $Script:QueryDetailForm = [PSCustomObject]@{ Query = [PSCustomObject]@{ DoId = "42"; DisplayName = "Accounts" }; Definition = [PSCustomObject]@{ Closed = 0 } }
        $Script:QueryDetailForm.Definition | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed++ }
        Mock Open-SqlQueryInActiveTab { "tab" }
        Mock Open-SqlQueryInTab { "tab" }
        Mock Request-QueryManagerClose { }
    }

    It 'Should open in the active tab with -InPlace, and close both windows' {
        Invoke-QueryDetailOpen -InPlace

        Should -Invoke Open-SqlQueryInActiveTab -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }
        Should -Invoke Open-SqlQueryInTab -Times 0 -Exactly
        Should -Invoke Request-QueryManagerClose -Times 1 -Exactly
        $Script:QueryDetailForm.Definition.Closed | Should -Be 1
    }

    It 'Should open in a new tab without -InPlace, and close both windows' {
        Invoke-QueryDetailOpen

        Should -Invoke Open-SqlQueryInTab -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }
        Should -Invoke Open-SqlQueryInActiveTab -Times 0 -Exactly
        $Script:QueryDetailForm.Definition.Closed | Should -Be 1
    }

    It 'Should keep both windows open when the query was not opened (<Case>)' -ForEach @(
        @{ Case = 'in place'; InPlace = $true }
        @{ Case = 'new tab'; InPlace = $false }
    ) {
        Mock Open-SqlQueryInActiveTab { }
        Mock Open-SqlQueryInTab { }

        Invoke-QueryDetailOpen -InPlace:$InPlace

        Should -Invoke Request-QueryManagerClose -Times 0 -Exactly
        $Script:QueryDetailForm.Definition.Closed | Should -Be 0
    }
}
