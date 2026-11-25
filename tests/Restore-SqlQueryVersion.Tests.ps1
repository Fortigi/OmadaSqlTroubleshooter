#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManagement.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Restore-SqlQueryVersion.ps1")
    . (Join-Path $Script:QueryPrivatePath "Set-TabEditorText.ps1")
    . (Join-Path $Script:QueryPrivatePath "ConvertTo-JavaScriptLiteral.ps1")

    function Get-ActiveTabSession { $script:TestTab }
    function Push-ToEditor { param($ScriptToExecute) }
    function Update-TabHeaderTitle { param($TabSession) }
    function Open-SqlQueryInTab { param($DoId, $DisplayName, $RestoreText) }
    function Request-QueryManagerClose { }
}

Describe 'Restore-SqlQueryVersion' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState
        $Script:Webview = [PSCustomObject]@{ Object = [PSCustomObject]@{ CoreWebView2 = "ready" } }
        Mock Push-ToEditor { }
        Mock Open-SqlQueryInTab { }
        Mock Request-QueryManagerClose { }
    }

    It 'Should put the version in the active tab''s editor as an unsaved change (<Case>)' -ForEach @(
        @{ Case = 'its own query'; DoId = "42" }
        @{ Case = 'no query named'; DoId = $null }
    ) {
        Restore-SqlQueryVersion -DoId $DoId -QueryName "Accounts" -Text "SELECT old"

        Should -Invoke Push-ToEditor -Times 1 -Exactly -ParameterFilter { $ScriptToExecute -eq 'window.setEditorValue("SELECT old");' }
        $Script:RunTimeData.CurrentQueryText | Should -Be "SELECT old"
        $script:TestTab.EditorText | Should -Be "SELECT old"
        $script:TestTab.IsDirty | Should -BeTrue
        Should -Invoke Open-SqlQueryInTab -Times 0 -Exactly
    }

    It 'Should restore another query into its own tab and close the query manager' {
        Restore-SqlQueryVersion -DoId "55" -QueryName "Fresh" -Text "SELECT old"

        Should -Invoke Open-SqlQueryInTab -Times 1 -Exactly -ParameterFilter { $DoId -eq "55" -and $DisplayName -eq "Fresh" -and $RestoreText -eq "SELECT old" }
        Should -Invoke Request-QueryManagerClose -Times 1 -Exactly
        Should -Invoke Push-ToEditor -Times 0 -Exactly
        $script:TestTab.IsDirty | Should -BeFalse
    }

    It 'Should restore nothing, with a warning, while the editor is not ready' {
        $Script:Webview = [PSCustomObject]@{ Object = $null }

        Restore-SqlQueryVersion -DoId "42" -QueryName "Accounts" -Text "SELECT old"

        Should -Invoke Push-ToEditor -Times 0 -Exactly
        $script:TestTab.IsDirty | Should -BeFalse
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match "not ready"
    }
}
