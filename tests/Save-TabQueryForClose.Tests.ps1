#Requires -Version 7.0
# Closing saves synchronously, from the text Monaco last reported, so nothing is torn down before the
# save is known to have worked.

BeforeAll {
    . (Join-Path $PSScriptRoot "CloseFlow.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Save-TabQueryForClose.ps1")
}

Describe 'Save-TabQueryForClose' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState
        $script:TestTab.IsDirty = $true
        Mock Save-Query { [PSCustomObject]@{ Id = 42; DisplayName = "Accounts" } }
        Mock Request-NewSqlQueryName { "Chosen" }
        Mock Update-TabHeaderTitle { }
        Mock Sync-AdHocQueryDraft { }
    }

    It 'Should save a selected query from the reported editor text' {
        Save-TabQueryForClose -TabSession $script:TestTab -Kind SaveExisting | Should -Be "Saved"

        $Script:RunTimeData.QueryText | Should -Be "SELECT on screen"
        Should -Invoke Save-Query -Times 1 -Exactly -ParameterFilter { -not $NewQuery }
        Should -Invoke Request-NewSqlQueryName -Times 0 -Exactly
    }

    It 'Should mark the tab clean and drop its draft after saving' {
        $null = Save-TabQueryForClose -TabSession $script:TestTab -Kind SaveExisting

        $script:TestTab.IsDirty | Should -BeFalse
        Should -Invoke Update-TabHeaderTitle -Times 1 -Exactly
        Should -Invoke Sync-AdHocQueryDraft -Times 1 -Exactly
    }

    It 'Should not ask for or set a name when saving a selected query' {
        $null = Save-TabQueryForClose -TabSession $script:TestTab -Kind SaveExisting

        $Script:RunTimeData.PendingQueryName | Should -BeNullOrEmpty
        Should -Invoke Request-NewSqlQueryName -Times 0 -Exactly
    }

    It 'Should ask for a name and save an ad-hoc query as a new query' {
        Save-TabQueryForClose -TabSession $script:TestTab -Kind SaveNew | Should -Be "Saved"

        $Script:RunTimeData.PendingQueryName | Should -Be "Chosen"
        Should -Invoke Request-NewSqlQueryName -Times 1 -Exactly -ParameterFilter { $Message -match "Query1" }
        Should -Invoke Save-Query -Times 1 -Exactly -ParameterFilter { $NewQuery }
    }

    It 'Should save the text waiting for an editor that never loaded' {
        $script:TestTab.EditorText = $null
        $script:TestTab | Add-Member -NotePropertyName PendingEditorText -NotePropertyValue "SELECT pending" -Force

        $null = Save-TabQueryForClose -TabSession $script:TestTab -Kind SaveExisting

        $Script:RunTimeData.QueryText | Should -Be "SELECT pending"
    }

    It 'Should report a cancelled name prompt as Cancelled, without saving' {
        Mock Request-NewSqlQueryName { $null }

        Save-TabQueryForClose -TabSession $script:TestTab -Kind SaveNew | Should -Be "Cancelled"
        Should -Invoke Save-Query -Times 0 -Exactly
        $script:TestTab.IsDirty | Should -BeTrue
    }

    It 'Should report <Case> as Failed and keep the tab dirty' -ForEach @(
        @{ Case = 'no result'; Throws = $false; Result = $null }
        @{ Case = 'an ErrorRecord'; Throws = $false; Result = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("x"), "x", "NotSpecified", $null) }
        @{ Case = 'a throw'; Throws = $true; Result = $null }
    ) {
        Mock Save-Query { if ($Throws) { throw "boom" } else { $Result } }

        Save-TabQueryForClose -TabSession $script:TestTab -Kind SaveExisting | Should -Be "Failed"
        $script:TestTab.IsDirty | Should -BeTrue
        Should -Invoke Sync-AdHocQueryDraft -Times 0 -Exactly
    }
}
