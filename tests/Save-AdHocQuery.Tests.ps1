#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Get-TabEditorText.ps1")
    . (Join-Path $Script:QueryPrivatePath "Save-AdHocQuery.ps1")

    function Get-ActiveTabSession { $script:TestTab }
    function Request-NewSqlQueryName { param($TabSession, $Message) }
    function Invoke-SaveEditorValue { param([switch]$NewQuery) }
}

Describe 'Save-AdHocQuery' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState -DoId $null
        Mock Request-NewSqlQueryName { "Chosen" }
        Mock Invoke-SaveEditorValue { }
    }

    It 'Should save the editor as a new query under the chosen name' {
        Save-AdHocQuery

        $Script:MainForm.Elements.TextBoxDisplayName.Text | Should -Be "Chosen"
        Should -Invoke Invoke-SaveEditorValue -Times 1 -Exactly -ParameterFilter { $NewQuery }
    }

    It 'Should not offer to save an empty editor' {
        $script:TestTab.EditorText = "  "

        Save-AdHocQuery

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

        Save-AdHocQuery

        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
        Should -Invoke Invoke-SaveEditorValue -Times 0 -Exactly
    }

    It 'Should leave the buttons to the asynchronous save when it starts one' {
        Save-AdHocQuery

        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeFalse
    }
}
