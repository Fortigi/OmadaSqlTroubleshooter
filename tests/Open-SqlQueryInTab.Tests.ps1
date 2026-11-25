#Requires -Version 7.0
# A query already open is shown in its tab, never opened twice; otherwise a new tab is opened with the
# active tab's connection. A restored version reaches the editor either way.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Open-SqlQueryInTab.ps1")
    . (Join-Path $Script:QueryPrivatePath "Set-TabEditorText.ps1")
    . (Join-Path $Script:QueryPrivatePath "ConvertTo-JavaScriptLiteral.ps1")

    function Get-TabControlSessions { $script:TabControl }
    function Set-ActiveTabContext { param($TabSession) $Script:ActiveTabId = $TabSession.Id }
    function Get-ActiveTabSession { $Script:Tabs | Where-Object { $_.Id -eq $Script:ActiveTabId } | Select-Object -First 1 }
    function Get-TabConnectionStatus { param($TabSession) $true }
    function New-TabConfigFromTab { param($SourceTab, $CurrentSqlQuery) [PSCustomObject]@{ Id = "new"; CurrentSqlQuery = $CurrentSqlQuery } }
    function New-TabSession { param($RestoreFrom, [switch]$AutoConnect) }
    function Push-ToEditor { param($ScriptToExecute) }
    function Update-TabHeaderTitle { param($TabSession) }
}

Describe 'Open-SqlQueryInTab' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState -DoId 7 -Name "Other"
        $script:Holder = [PSCustomObject]@{
            Id          = "tab-2"
            DisplayName = "Accounts"
            IsDirty     = $false
            TabItem     = "item-2"
            AppConfig   = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DoId = 42 } }
        }
        $Script:Tabs = @($script:TestTab, $script:Holder)
        $script:TabControl = [PSCustomObject]@{ SelectedItem = $null }
        Mock New-TabSession { [PSCustomObject]@{ Id = "new"; RestoreFrom = $RestoreFrom } }
        Mock Push-ToEditor { }
        Mock Set-ActiveTabContext { $Script:ActiveTabId = $TabSession.Id }
    }

    It 'Should select the tab that already holds the query instead of opening another' {
        $Tab = Open-SqlQueryInTab -DoId "42" -DisplayName "Accounts"

        $Tab.Id | Should -Be "tab-2"
        $script:TabControl.SelectedItem | Should -Be "item-2"
        $Script:ActiveTabId | Should -Be "tab-2"
        Should -Invoke New-TabSession -Times 0 -Exactly
        Should -Invoke Push-ToEditor -Times 0 -Exactly
    }

    It 'Should push a restored version into the tab that holds the query, as an unsaved change' {
        $null = Open-SqlQueryInTab -DoId "42" -DisplayName "Accounts" -RestoreText "SELECT old"

        Should -Invoke Push-ToEditor -Times 1 -Exactly -ParameterFilter { $ScriptToExecute -eq 'window.setEditorValue("SELECT old");' }
        $script:Holder.EditorText | Should -Be "SELECT old"
        $script:Holder.IsDirty | Should -BeTrue
    }

    It 'Should open a new, connected tab holding the query when none does' {
        $Tab = Open-SqlQueryInTab -DoId "55" -DisplayName "Fresh"

        $Tab.Id | Should -Be "new"
        Should -Invoke New-TabSession -Times 1 -Exactly -ParameterFilter {
            $AutoConnect -and $RestoreFrom.CurrentSqlQuery.DoId -eq "55" -and $RestoreFrom.CurrentSqlQuery.DisplayName -eq "Fresh" -and $RestoreFrom.CurrentSqlQuery.FullName -eq "Fresh - 55"
        }
    }

    It 'Should leave a restored version waiting on a new tab until its editor loads' {
        $Tab = Open-SqlQueryInTab -DoId "55" -DisplayName "Fresh" -RestoreText "SELECT old"

        $Tab.PendingRestoreText | Should -Be "SELECT old"
        Should -Invoke Push-ToEditor -Times 0 -Exactly
    }

    It 'Should not leave a restore waiting when none was asked for' {
        $Tab = Open-SqlQueryInTab -DoId "55" -DisplayName "Fresh"

        $Tab.PSObject.Properties.Name | Should -Not -Contain "PendingRestoreText"
    }

    It 'Should return nothing when no tab could be opened' {
        Mock New-TabSession { $null }

        Open-SqlQueryInTab -DoId "55" -DisplayName "Fresh" -RestoreText "x" | Should -BeNullOrEmpty
    }

    It 'Should refuse without a tab to take the connection from' {
        $Script:Tabs = @($script:Holder)
        $Script:ActiveTabId = "none"

        Open-SqlQueryInTab -DoId "55" -DisplayName "Fresh" | Should -BeNullOrEmpty
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match "connect"
    }
}
