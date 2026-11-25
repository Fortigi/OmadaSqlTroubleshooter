#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-CachedQueryName.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-UniqueQueryName.ps1")
    . (Join-Path $Script:QueryPrivatePath "Rename-SqlQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Request-NewSqlQueryName.ps1")

    function Read-QueryNameInput { param($Title, $Message, $DefaultName, $CurrentName, $ExistingNames, $OkText) }
    function Test-SqlQueryNameTaken { param($Name, $ExcludeDoId) }
}

Describe 'Request-NewSqlQueryName' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState -DoId $null
        Mock Read-QueryNameInput { [PSCustomObject]@{ IsValid = $true; Name = "Chosen" } }
        Mock Test-SqlQueryNameTaken { $false }
    }

    It 'Should suggest the name proposed for the tab when there is one' {
        $script:TestTab.ProposedQueryName = "Proposed name"

        $null = Request-NewSqlQueryName -TabSession $script:TestTab

        Should -Invoke Read-QueryNameInput -Times 1 -Exactly -ParameterFilter { $DefaultName -eq "Proposed name" -and $OkText -eq "Save" -and ($ExistingNames -contains "Accounts") }
    }

    It 'Should suggest the name it was given before the proposed one (Save as)' {
        $script:TestTab.ProposedQueryName = "Proposed name"

        $null = Request-NewSqlQueryName -TabSession $script:TestTab -DefaultName "Accounts1"

        Should -Invoke Read-QueryNameInput -Times 1 -Exactly -ParameterFilter { $DefaultName -eq "Accounts1" }
    }

    It 'Should suggest the next free Query{#} from the tab''s number otherwise' {
        $Script:RunTimeData.QueryListCache.QueryList = @(@{ 1 = "Query3" })

        $null = Request-NewSqlQueryName -TabSession $script:TestTab

        Should -Invoke Read-QueryNameInput -Times 1 -Exactly -ParameterFilter { $DefaultName -eq "Query4" }
    }

    It 'Should pass the message through' {
        $null = Request-NewSqlQueryName -TabSession $script:TestTab -Message "Save it as:"

        Should -Invoke Read-QueryNameInput -Times 1 -Exactly -ParameterFilter { $Message -eq "Save it as:" }
    }

    It 'Should return the chosen name when the tenant has no query with it' {
        Request-NewSqlQueryName -TabSession $script:TestTab | Should -Be "Chosen"
        Should -Invoke Test-SqlQueryNameTaken -Times 1 -Exactly -ParameterFilter { $Name -eq "Chosen" }
    }

    It 'Should return nothing when the user cancels' {
        Mock Read-QueryNameInput { $null }

        Request-NewSqlQueryName -TabSession $script:TestTab | Should -BeNullOrEmpty
        Should -Invoke Test-SqlQueryNameTaken -Times 0 -Exactly
    }

    It 'Should return nothing, with the reason, when the name cannot be used (<Case>)' -ForEach @(
        @{ Case = 'taken'; Taken = $true; Reason = "already exists" }
        @{ Case = 'unknown'; Taken = $null; Reason = "Could not check" }
    ) {
        Mock Test-SqlQueryNameTaken { $Taken }

        Request-NewSqlQueryName -TabSession $script:TestTab | Should -BeNullOrEmpty
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match $Reason
    }
}
