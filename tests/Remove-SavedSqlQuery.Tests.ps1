#Requires -Version 7.0
# Delete removes the query object but never the user's text: the tab becomes an unsaved ad-hoc query.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-SelectedSavedQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "New-OmadaQueryRequest.ps1")
    . (Join-Path $Script:QueryPrivatePath "Remove-SavedSqlQuery.ps1")

    function Open-ChoiceForm { param($Title, $Message, $LeftButtonText, $RightButtonText) }
    function Invoke-SavedQueryRequest { param($Request) }
    function Clear-RecentSqlQueryObject { param($DoId) }
    function Update-QueryInConnectedPoolTabs { param($DoId, $DisplayName, [switch]$Remove) }
    function Update-SavedQueryCommandState { }
    function Get-ActiveTabSession { $script:TestTab }
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
        $Script:MainForm.Elements.TextBoxDisplayName.Text | Should -Be "Accounts"
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
}
