#Requires -Version 7.0
# Rename sends the NAME only, after local and tenant checks, and updates every tab of the pool.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-SelectedSavedQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-CachedQueryName.ps1")
    . (Join-Path $Script:QueryPrivatePath "New-OmadaQueryRequest.ps1")
    . (Join-Path $Script:QueryPrivatePath "Rename-SqlQuery.ps1")

    function Read-QueryNameInput { param($Title, $Message, $DefaultName, $CurrentName, $ExistingNames, $OkText) }
    function Test-SqlQueryNameTaken { param($Name, $ExcludeDoId) }
    function Invoke-SavedQueryRequest { param($Request) }
    function Clear-RecentSqlQueryObject { param($DoId) }
    function Set-ConfigProperty {
        param([Parameter(ValueFromPipeline = $true)]$Value, $Property)
        begin { $Values = @() }
        process { $Values += $Value }
        end { $Script:AppConfig.CurrentSqlQuery = [PSCustomObject]@{ DoId = $Values[0]; DisplayName = $Values[1]; FullName = "{0} - {1}" -f $Values[1], $Values[0] } }
    }
    function Update-QueryInConnectedPoolTabs { param($DoId, $DisplayName, [switch]$Remove) }
    function Get-ActiveTabSession { $script:TestTab }
    function Update-TabHeaderTitle { param($TabSession) }
}

Describe 'Rename-SqlQuery' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState
        Mock Read-QueryNameInput { [PSCustomObject]@{ IsValid = $true; IsUnchanged = $false; Name = "Renamed" } }
        Mock Test-SqlQueryNameTaken { $false }
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = $null; Message = $null } }
        Mock Clear-RecentSqlQueryObject { }
        Mock Update-QueryInConnectedPoolTabs { }
        Mock Update-TabHeaderTitle { }
    }

    It 'Should ask for the new name, suggesting the current one' {
        Rename-SqlQuery

        Should -Invoke Read-QueryNameInput -Times 1 -Exactly -ParameterFilter {
            $DefaultName -eq "Accounts" -and $CurrentName -eq "Accounts" -and $OkText -eq "Rename" -and ($ExistingNames -contains "Other")
        }
    }

    It 'Should PUT only the new name onto the selected query' {
        Rename-SqlQuery

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter {
            $Request.Method -eq "PUT" -and $Request.Uri -eq "https://t/odata/dataobjects/C_P_SQLTROUBLESHOOTING(42)" -and $Request.Body.NAME -eq "Renamed" -and $Request.Body.Count -eq 1
        }
    }

    It 'Should check the tenant for the name, excluding the query itself' {
        Rename-SqlQuery

        Should -Invoke Test-SqlQueryNameTaken -Times 1 -Exactly -ParameterFilter { $Name -eq "Renamed" -and $ExcludeDoId -eq "42" }
    }

    It 'Should apply the new name to the tab and the pool' {
        Rename-SqlQuery

        $Script:AppConfig.CurrentSqlQuery.DoId | Should -Be "42"
        $Script:AppConfig.CurrentSqlQuery.DisplayName | Should -Be "Renamed"
        $Script:RunTimeData.CurrentSqlQuery.DisplayName | Should -Be "Renamed"
        $Script:RunTimeData.CurrentSqlQuery.FullName | Should -Be "Renamed - 42"
        $Script:MainForm.Elements.TextBoxDisplayName.Text | Should -Be "Renamed"
        Should -Invoke Update-QueryInConnectedPoolTabs -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Renamed" -and -not $Remove }
        Should -Invoke Clear-RecentSqlQueryObject -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" }
        Should -Invoke Update-TabHeaderTitle -Times 1 -Exactly
    }

    It 'Should prefer the name the tenant answered with' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ DisplayName = "Renamed (tenant)" } } }

        Rename-SqlQuery

        $Script:MainForm.Elements.TextBoxDisplayName.Text | Should -Be "Renamed (tenant)"
    }

    It 'Should leave the editor text and the dirty flag alone' {
        $script:TestTab.IsDirty = $true

        Rename-SqlQuery

        $script:TestTab.IsDirty | Should -BeTrue
        $Script:RunTimeData.CurrentQueryText | Should -Be "SELECT saved"
    }

    It 'Should do nothing when <Case>' -ForEach @(
        @{ Case = 'the user cancels'; Reply = $null }
        @{ Case = 'the name is unchanged'; Reply = [PSCustomObject]@{ IsValid = $true; IsUnchanged = $true; Name = "Accounts" } }
    ) {
        Mock Read-QueryNameInput { $Reply }

        Rename-SqlQuery

        Should -Invoke Test-SqlQueryNameTaken -Times 0 -Exactly
        Should -Invoke Invoke-SavedQueryRequest -Times 0 -Exactly
    }

    It 'Should not rename onto a name the tenant already has' {
        Mock Test-SqlQueryNameTaken { $true }

        Rename-SqlQuery

        Should -Invoke Invoke-SavedQueryRequest -Times 0 -Exactly
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match "already exists"
    }

    It 'Should not rename when the tenant could not be asked' {
        Mock Test-SqlQueryNameTaken { $null }

        Rename-SqlQuery

        Should -Invoke Invoke-SavedQueryRequest -Times 0 -Exactly
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match "Could not check"
    }

    It 'Should report a refused rename and change nothing locally' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = "401" } }

        Rename-SqlQuery

        ($script:QueryLog | Where-Object LogType -eq "ERROR").Message | Should -Match "Renaming query 'Accounts' failed: 401"
        $Script:MainForm.Elements.TextBoxDisplayName.Text | Should -Be "Accounts"
        Should -Invoke Update-QueryInConnectedPoolTabs -Times 0 -Exactly
    }

    It 'Should not ask anything for an ad-hoc query' {
        New-QueryTestState -DoId $null

        Rename-SqlQuery

        Should -Invoke Read-QueryNameInput -Times 0 -Exactly
    }

    It 'Should contain a failure instead of throwing' {
        Mock Read-QueryNameInput { throw "dialog failed" }

        { Rename-SqlQuery } | Should -Not -Throw
        ($script:QueryLog | Where-Object LogType -eq "ERROR").Message | Should -Match "dialog failed"
    }
}

Describe 'Get-SavedQueryDisplayName' -Tag 'Unit' {
    It 'Should use the name in the answer' {
        Get-SavedQueryDisplayName -Result ([PSCustomObject]@{ DisplayName = "A" }) -FallbackName "B" | Should -Be "A"
    }

    It 'Should fall back to the name that was sent (<Case>)' -ForEach @(
        @{ Case = 'no answer'; Result = $null }
        @{ Case = 'no name in it'; Result = [PSCustomObject]@{ DisplayName = " " } }
    ) {
        Get-SavedQueryDisplayName -Result $Result -FallbackName "B" | Should -Be "B"
    }
}
