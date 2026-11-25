#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "New-QueryManagerRequest.ps1")
    . (Join-Path $Script:QueryPrivatePath "Rename-SqlQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "New-SqlQueryObject.ps1")

    function Read-QueryNameInput { param($Title, $Message, $DefaultName, $CurrentName, $ExistingNames, $OkText) }
    function Test-SqlQueryNameTaken { param($Name, $ExcludeDoId) }
    function Invoke-SavedQueryRequest { param($Request) }
    function Add-QueryToConnectedPoolTabs { param($DoId, $DisplayName, $FullName) }
}

Describe 'New-SqlQueryObject' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState
        $Script:AppConfig | Add-Member -NotePropertyName CurrentDataConnection -NotePropertyValue ([PSCustomObject]@{ DoId = "3" }) -Force
        Mock Read-QueryNameInput { [PSCustomObject]@{ IsValid = $true; Name = "Fresh" } }
        Mock Test-SqlQueryNameTaken { $false }
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ Id = 200; DisplayName = "Fresh" } } }
        Mock Add-QueryToConnectedPoolTabs { }
    }

    It 'Should ask a name against the names the manager shows' {
        $null = New-SqlQueryObject -ExistingNames @("Accounts")

        Should -Invoke Read-QueryNameInput -Times 1 -Exactly -ParameterFilter { $OkText -eq "Create" -and ($ExistingNames -contains "Accounts") }
    }

    It 'Should create it with a placeholder comment and the active connection' {
        $Created = New-SqlQueryObject

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter {
            $Request.Method -eq "POST" -and $Request.Body.NAME -eq "Fresh" -and $Request.Body.C_QUERY -eq "-- Fresh" -and $Request.Body.C_SQLTROUBLESHOOTING_DATACONNECTION.Id -eq "3"
        }
        $Created.DoId | Should -Be "200"
        $Created.DisplayName | Should -Be "Fresh"
    }

    It 'Should add the new query to the pool''s query lists' {
        $null = New-SqlQueryObject

        Should -Invoke Add-QueryToConnectedPoolTabs -Times 1 -Exactly -ParameterFilter { $DoId -eq "200" -and $DisplayName -eq "Fresh" -and $FullName -eq "Fresh - 200" }
    }

    It 'Should create nothing when <Case>' -ForEach @(
        @{ Case = 'the user cancels'; Name = $null; Taken = $false }
        @{ Case = 'the name is taken'; Name = [PSCustomObject]@{ Name = "Fresh" }; Taken = $true }
        @{ Case = 'the tenant cannot be asked'; Name = [PSCustomObject]@{ Name = "Fresh" }; Taken = $null }
    ) {
        Mock Read-QueryNameInput { $Name }
        Mock Test-SqlQueryNameTaken { $Taken }

        New-SqlQueryObject | Should -BeNullOrEmpty
        Should -Invoke Invoke-SavedQueryRequest -Times 0 -Exactly
    }

    It 'Should report a refused create (<Case>)' -ForEach @(
        @{ Case = 'refused'; Response = [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = "401" } }
        @{ Case = 'no id in the answer'; Response = [PSCustomObject]@{ Succeeded = $true; Result = $null; Message = $null } }
    ) {
        Mock Invoke-SavedQueryRequest { $Response }

        New-SqlQueryObject | Should -BeNullOrEmpty
        ($script:QueryLog | Where-Object LogType -eq "ERROR").Message | Should -Match "Creating query 'Fresh' failed"
        Should -Invoke Add-QueryToConnectedPoolTabs -Times 0 -Exactly
    }
}
