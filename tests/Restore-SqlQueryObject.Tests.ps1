#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Restore-SqlQueryObject.ps1")
    . (Join-Path $PrivatePath "New-QueryManagerRequest.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { } }
    function Write-ContainedErrorLog { param([Parameter(ValueFromPipeline = $true)]$Message) process { $script:Errors += , $Message } }
    function Test-SqlQueryNameTaken { param($Name, $ExcludeDoId) }
    function Open-ChoiceForm { param($Title, $Message, $LeftButtonText, $RightButtonText) }
    function Invoke-SavedQueryRequest { param($Request) }
}

Describe 'Restore-SqlQueryObject' -Tag 'Unit' {
    BeforeEach {
        $script:Errors = @()
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://t" }
        Mock Test-SqlQueryNameTaken { $false }
        Mock Open-ChoiceForm { $true }
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true } }
    }

    It 'Should undelete the query' {
        Restore-SqlQueryObject -DoId "42" -DisplayName "Accounts" | Should -BeTrue

        Should -Invoke Test-SqlQueryNameTaken -Times 1 -Exactly -ParameterFilter { $Name -eq "Accounts" -and $ExcludeDoId -eq "42" }
        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like "https://t/*UndeleteDataObject" -and ($Request.Body | ConvertFrom-Json).id -eq "42" }
        Should -Invoke Open-ChoiceForm -Times 0 -Exactly
    }

    It 'Should ask first when another query has the name, and stop on Cancel' {
        Mock Test-SqlQueryNameTaken { $true }
        Mock Open-ChoiceForm { $false }

        Restore-SqlQueryObject -DoId "42" -DisplayName "Accounts" | Should -BeFalse

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Message -match "already named 'Accounts'" }
        Should -Invoke Invoke-SavedQueryRequest -Times 0 -Exactly
    }

    It 'Should restore all the same when asked to' {
        Mock Test-SqlQueryNameTaken { $true }

        Restore-SqlQueryObject -DoId "42" -DisplayName "Accounts" | Should -BeTrue
        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly
    }

    It 'Should restore when the name cannot be checked' {
        Mock Test-SqlQueryNameTaken { $null }

        Restore-SqlQueryObject -DoId "42" -DisplayName "Accounts" | Should -BeTrue
        Should -Invoke Open-ChoiceForm -Times 0 -Exactly
    }

    It 'Should report a failure and say false' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $false; Message = "403" } }

        Restore-SqlQueryObject -DoId "42" -DisplayName "Accounts" | Should -BeFalse
        $script:Errors | Should -Match "Restoring query 'Accounts' failed: 403"
    }
}
