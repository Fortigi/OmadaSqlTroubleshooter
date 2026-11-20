#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "New-OmadaQueryRequest.ps1")
    . (Join-Path $PrivatePath "Test-SqlQueryNameTaken.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType) process { } }
    function Invoke-SavedQueryRequest { param($Request) }
    $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://t" }
}

Describe 'Test-SqlQueryNameTaken' -Tag 'Unit' {
    It 'Should ask the tenant with the escaped name' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ value = @() } } }

        $null = Test-SqlQueryNameTaken -Name "Bob's"

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Method -eq "GET" -and $Request.Uri -like "https://t/*NAME eq 'Bob''s'" }
    }

    It 'Should report a free name' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ value = @() } } }

        Test-SqlQueryNameTaken -Name "Free" | Should -BeFalse
    }

    It 'Should report a taken name' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ value = @([PSCustomObject]@{ Id = 9 }) } } }

        Test-SqlQueryNameTaken -Name "Taken" | Should -BeTrue
    }

    It 'Should not count the query being renamed as a clash with itself' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ value = @([PSCustomObject]@{ Id = 9 }) } } }

        Test-SqlQueryNameTaken -Name "Same" -ExcludeDoId "9" | Should -BeFalse
    }

    It 'Should still see another query beside the one being renamed' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ value = @([PSCustomObject]@{ Id = 9 }, [PSCustomObject]@{ Id = 10 }) } } }

        Test-SqlQueryNameTaken -Name "Same" -ExcludeDoId 9 | Should -BeTrue
    }

    It 'Should answer $null, not a guess, when the tenant could not be asked (<Case>)' -ForEach @(
        @{ Case = 'request failed'; Response = [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = "boom" } }
        @{ Case = 'no request made'; Response = [PSCustomObject]@{ Succeeded = $true; Result = $null } }
    ) {
        Mock Invoke-SavedQueryRequest { $Response }

        $Answer = Test-SqlQueryNameTaken -Name "Any"

        $null -eq $Answer | Should -BeTrue
    }
}
