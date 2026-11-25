#Requires -Version 7.0
# Delete removes the query object but never the user's text: the tab becomes an unsaved ad-hoc query.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-SelectedSavedQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "New-OmadaQueryRequest.ps1")
    . (Join-Path $Script:QueryPrivatePath "Remove-SavedSqlQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Clear-TabSavedQuerySelection.ps1")

    function Open-ChoiceForm { param($Title, $Message, $LeftButtonText, $RightButtonText) }
    function Invoke-SavedQueryRequest { param($Request) }
    function Clear-RecentSqlQueryObject { param($DoId) }
    function Update-QueryInConnectedPoolTabs { param($DoId, $DisplayName, [switch]$Remove) }
    function Update-SavedQueryCommandState { }
    function Get-ActiveTabSession { $Script:Tabs | Where-Object { $_.Id -eq $Script:ActiveTabId } | Select-Object -First 1 }
    function Set-ActiveTabContext { param($TabSession) $Script:ActiveTabId = $TabSession.Id; $Script:AppConfig = $TabSession.AppConfig; $Script:RunTimeData = $TabSession.RunTimeData; $Script:MainForm.Elements = $TabSession.Elements }
    function Update-TabHeaderTitle { param($TabSession) }
    function Sync-AdHocQueryDraft { param($TabSession) }
}

Describe 'Remove-SavedSqlQuery' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState
        Mock Open-ChoiceForm { $true }
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = $null; Message = $null } }
        Mock Clear-RecentSqlQueryObject { }
        Mock Update-QueryInConnectedPoolTabs { }
        Mock Update-SavedQueryCommandState { }
        Mock Update-TabHeaderTitle { }
        Mock Sync-AdHocQueryDraft { }
        Mock Set-ActiveTabContext { $Script:ActiveTabId = $TabSession.Id; $Script:AppConfig = $TabSession.AppConfig; $Script:RunTimeData = $TabSession.RunTimeData; $Script:MainForm.Elements = $TabSession.Elements }
    }

    It 'Should ask first, naming the query and what happens to its text' {
        Remove-SavedSqlQuery

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter {
            $Message -match "Delete query 'Accounts' from Omada" -and $Message -match "stays in the editor" -and $LeftButtonText -eq "Delete" -and $RightButtonText -eq "Cancel"
        }
    }

    It 'Should DELETE the selected query' {
        Remove-SavedSqlQuery

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter {
            $Request.Method -eq "DELETE" -and $Request.Uri -eq "https://t/odata/dataobjects/C_P_SQLTROUBLESHOOTING(42)"
        }
    }

    It 'Should do nothing when the user does not confirm (<Case>)' -ForEach @(
        @{ Case = 'Cancel'; Choice = $false }
        @{ Case = 'closing the dialog'; Choice = $null }
    ) {
        Mock Open-ChoiceForm { $Choice }

        Remove-SavedSqlQuery

        Should -Invoke Invoke-SavedQueryRequest -Times 0 -Exactly
        $Script:AppConfig.CurrentSqlQuery.DoId | Should -Be 42
    }

    It 'Should turn the tab into an unsaved ad-hoc query that keeps the text' {
        Remove-SavedSqlQuery

        $Script:AppConfig.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Script:AppConfig.CurrentSqlQuery.FullName | Should -BeNullOrEmpty
        $Script:RunTimeData.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Script:RunTimeData.CurrentSqlQuery.DisplayName | Should -BeNullOrEmpty
        $Script:RunTimeData.CurrentQueryText | Should -BeNullOrEmpty
        $script:TestTab.AppConfig.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $script:TestTab.IsDirty | Should -BeTrue
        $script:TestTab.DraftText | Should -Be "SELECT on screen"
    }

    It 'Should clear the selection and keep the name for saving it again' {
        Remove-SavedSqlQuery

        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem | Should -BeNullOrEmpty
        $Script:MainForm.Elements.ComboBoxSelectQuery.Text | Should -Be ""
        $script:TestTab.ProposedQueryName | Should -Be "Accounts" -Because "the tab keeps its name, and saving it again suggests it"
    }

    It 'Should drop the query from the pool, update the commands and keep the draft' {
        Remove-SavedSqlQuery

        Should -Invoke Clear-RecentSqlQueryObject -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" }
        Should -Invoke Update-QueryInConnectedPoolTabs -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $Remove }
        Should -Invoke Update-SavedQueryCommandState -Times 1 -Exactly
        Should -Invoke Sync-AdHocQueryDraft -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "tab-1" }
    }

    It 'Should report a refused delete and change nothing locally' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = "401" } }

        Remove-SavedSqlQuery

        ($script:QueryLog | Where-Object LogType -eq "ERROR").Message | Should -Match "Deleting query 'Accounts' failed: 401"
        $Script:AppConfig.CurrentSqlQuery.DoId | Should -Be 42
        $script:TestTab.IsDirty | Should -BeFalse
        Should -Invoke Update-QueryInConnectedPoolTabs -Times 0 -Exactly
    }

    It 'Should not ask anything without a saved query' {
        New-QueryTestState -DoId $null

        Remove-SavedSqlQuery

        Should -Invoke Open-ChoiceForm -Times 0 -Exactly
    }

    It 'Should contain a failure instead of throwing' {
        Mock Open-ChoiceForm { throw "dialog failed" }

        { Remove-SavedSqlQuery } | Should -Not -Throw
        ($script:QueryLog | Where-Object LogType -eq "ERROR").Message | Should -Match "dialog failed"
    }

    It 'Should report whether it deleted (<Case>)' -ForEach @(
        @{ Case = 'deleted'; Choice = $true; Succeeded = $true; Expected = $true }
        @{ Case = 'not confirmed'; Choice = $false; Succeeded = $true; Expected = $false }
        @{ Case = 'refused'; Choice = $true; Succeeded = $false; Expected = $false }
    ) {
        Mock Open-ChoiceForm { $Choice }
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $Succeeded; Result = $null; Message = "x" } }

        Remove-SavedSqlQuery | Should -Be $Expected
    }

    Context 'From the query manager, for a query open in a background tab' {
        BeforeEach {
            # The active tab holds another query; tab-2 holds the one being deleted.
            New-QueryTestState -DoId 7 -Name "Other"
            $script:Active = $script:TestTab
            $script:Elements2 = [PSCustomObject]@{
                ComboBoxSelectQuery = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Content = "Accounts - 42" }; Text = "Accounts - 42" }
            }
            $script:Holder = [PSCustomObject]@{
                Id                = "tab-2"
                DisplayName       = "Accounts"
                IsDirty           = $false
                EditorText        = "SELECT holder"
                DraftText         = $null
                ProposedQueryName = $null
                AppConfig         = [PSCustomObject]@{ BaseUrl = "https://t"; CurrentSqlQuery = [PSCustomObject]@{ DoId = 42; DisplayName = "Accounts"; FullName = "Accounts - 42" } }
                RunTimeData       = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DoId = 42; DisplayName = "Accounts"; FullName = "Accounts - 42" }; CurrentQueryText = "SELECT holder" }
                Elements          = $script:Elements2
            }
            $Script:Tabs = @($script:Active, $script:Holder)
        }

        It 'Should delete the query it was given, not the active tab''s' {
            Remove-SavedSqlQuery -DoId "42" -DisplayName "Accounts" | Should -BeTrue

            Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like "*(42)" }
        }

        It 'Should turn the holding tab into an ad-hoc query and leave the active tab alone' {
            $null = Remove-SavedSqlQuery -DoId "42" -DisplayName "Accounts"

            $script:Holder.AppConfig.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
            $script:Holder.IsDirty | Should -BeTrue
            $script:Holder.DraftText | Should -Be "SELECT holder"
            $script:Holder.ProposedQueryName | Should -Be "Accounts"
            $script:Elements2.ComboBoxSelectQuery.SelectedItem | Should -BeNullOrEmpty
            $script:Active.AppConfig.CurrentSqlQuery.DoId | Should -Be 7
            $Script:ActiveTabId | Should -Be "tab-1"
        }

        It 'Should not need the active tab to hold a saved query' {
            New-QueryTestState -DoId $null
            $Script:Tabs = @($script:TestTab, $script:Holder)

            Remove-SavedSqlQuery -DoId "42" -DisplayName "Accounts" | Should -BeTrue
            Should -Invoke Open-ChoiceForm -Times 1 -Exactly
        }
    }
}
