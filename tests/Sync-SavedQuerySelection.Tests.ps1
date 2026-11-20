#Requires -Version 7.0
# After an execute: a run that saved the query refreshes the selection from what was saved. An ad-hoc
# run saves nothing, and must not write "$null, $null" into CurrentSqlQuery - Set-ConfigProperty turns
# that into DoId 0, a query that does not exist, which the next start would then try to load.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Invoke-ExecuteQuery.ps1"))

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType) process { } }

    $script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
    function Set-ConfigProperty {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$Property)
        process { $script:ConfigWrites.Add([pscustomobject]@{ Property = $Property; Value = $InputObject }) }
    }

    $script:Refreshes = 0
    function Update-QueryList { param([switch]$ForceRefresh) $script:Refreshes++ }
}

Describe 'Sync-SavedQuerySelection' -Tag 'Unit' {
    BeforeEach {
        $script:ConfigWrites.Clear()
        $script:Refreshes = 0
        $script:Item = [PSCustomObject]@{ Content = "TestQuery - 100" }
        $Script:RunTimeData = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DisplayName = "TestQuery" } }
        $Script:AppConfig = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DoId = 100; FullName = "TestQuery - 100" } }
        $Script:MainForm = [PSCustomObject]@{
            Elements = [PSCustomObject]@{
                ComboBoxSelectQuery = [PSCustomObject]@{ Items = [System.Collections.ArrayList]@($script:Item); SelectedItem = $null }
            }
        }
    }

    It 'Should leave everything alone after an ad-hoc run, which saved nothing' {
        Sync-SavedQuerySelection -SaveResult $null

        $script:ConfigWrites.Count | Should -Be 0
        $script:Refreshes | Should -Be 0
        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem | Should -BeNullOrEmpty
    }

    It 'Should record the saved query and not refresh when its name is unchanged' {
        Sync-SavedQuerySelection -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" })

        $Written = @($script:ConfigWrites | Where-Object { $_.Property -eq "CurrentSqlQuery" })
        $Written.Value | Should -Be @(100, "TestQuery")
        $script:Refreshes | Should -Be 0
    }

    It 'Should refresh the list and select the query when its name changed' {
        Sync-SavedQuerySelection -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "Renamed" })

        $script:Refreshes | Should -Be 1
        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem | Should -Be $script:Item
    }
}
