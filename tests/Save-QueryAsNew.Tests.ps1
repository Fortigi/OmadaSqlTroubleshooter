#Requires -Version 7.0
# Save of an ad-hoc query, and Save as of any query: a name pop-up, then the create path.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Test-AdHocQuery.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-TabEditorText.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-CachedQueryName.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-IncrementedQueryName.ps1")
    . (Join-Path $Script:QueryPrivatePath "Save-QueryAsNew.ps1")

    function Get-ActiveTabSession { $script:TestTab }
    function Request-NewSqlQueryName { param($TabSession, $Message, $DefaultName) }
    function Invoke-SaveEditorValue { param([switch]$NewQuery) }
}

Describe 'Save-QueryAsNew' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState -DoId $null
        Mock Request-NewSqlQueryName { "Chosen" }
        Mock Invoke-SaveEditorValue { }
    }

    It 'Should create a query under the chosen name' {
        Save-QueryAsNew

        $Script:RunTimeData.PendingQueryName | Should -Be "Chosen"
        Should -Invoke Invoke-SaveEditorValue -Times 1 -Exactly -ParameterFilter { $NewQuery }
    }

    It 'Should pass the suggestion and the message to the name prompt' {
        Save-QueryAsNew -DefaultName "Suggested" -Message "Name it:"

        Should -Invoke Request-NewSqlQueryName -Times 1 -Exactly -ParameterFilter { $DefaultName -eq "Suggested" -and $Message -eq "Name it:" -and $TabSession.Id -eq "tab-1" }
    }

    It 'Should not offer to save an empty editor' {
        $script:TestTab.EditorText = "  "

        Save-QueryAsNew

        Should -Invoke Request-NewSqlQueryName -Times 0 -Exactly
        Should -Invoke Invoke-SaveEditorValue -Times 0 -Exactly
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match "empty"
    }

    It 'Should give the buttons back when nothing is saved (<Case>)' -ForEach @(
        @{ Case = 'empty editor'; Text = ""; Name = "x" }
        @{ Case = 'name prompt cancelled'; Text = "SELECT 1"; Name = $null }
    ) {
        $script:TestTab.EditorText = $Text
        Mock Request-NewSqlQueryName { $Name }

        Save-QueryAsNew

        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
        Should -Invoke Invoke-SaveEditorValue -Times 0 -Exactly
        $Script:RunTimeData.PendingQueryName | Should -BeNullOrEmpty
    }

    It 'Should leave the buttons to the asynchronous save when it starts one' {
        Save-QueryAsNew

        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeFalse
    }
}

Describe 'Save-SqlQueryAs' -Tag 'Unit' {
    BeforeEach {
        Mock Save-QueryAsNew { }
    }

    It 'Should suggest the next free numbered variant of a saved query''s name' {
        New-QueryTestState

        Save-SqlQueryAs

        Should -Invoke Save-QueryAsNew -Times 1 -Exactly -ParameterFilter { $DefaultName -eq "Accounts1" -and $Message -match "new query" }
    }

    It 'Should skip a numbered name that is already taken' {
        New-QueryTestState
        $Script:RunTimeData.QueryListCache.QueryList = @(@{ 42 = "Accounts" }, @{ 44 = "Accounts1" })

        Save-SqlQueryAs

        Should -Invoke Save-QueryAsNew -Times 1 -Exactly -ParameterFilter { $DefaultName -eq "Accounts2" }
    }

    It 'Should leave the suggestion to the name prompt for an ad-hoc query' {
        New-QueryTestState -DoId $null

        Save-SqlQueryAs

        Should -Invoke Save-QueryAsNew -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($DefaultName) }
    }
}
