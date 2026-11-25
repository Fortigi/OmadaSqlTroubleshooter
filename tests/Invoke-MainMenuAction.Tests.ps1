#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Invoke-MainMenuAction.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { } }
    function Get-ActiveTabSession { $script:ActiveTab }
    function Set-TabResultOutputMode { param($TabSession, $Mode) }
    function New-EmptyTabSession { }
    function Invoke-DuplicateTab { param($TabId, [switch]$WithoutQuery) }
    function Select-AdjacentTab { param($Direction) }
    function Close-TabSession { param($TabId) }
    function Close-OtherTabSessions { param($KeepTabId) }
    function Close-AllTabSessions { }
    function Open-AboutForm { }
    function Open-HelpForm { }
    function Open-GitHubIssue { param($Kind) }
}

Describe 'Invoke-MainMenuAction' -Tag 'Unit' {
    BeforeEach {
        $script:ActiveTab = [PSCustomObject]@{ TabId = "t1" }
        $Script:MainForm = [PSCustomObject]@{
            Definition = [PSCustomObject]@{ Closed = 0 }
            Elements   = @{
                ButtonSaveQuery          = [PSCustomObject]@{ Name = "Save"; IsEnabled = $true }
                ButtonDeleteQuery        = [PSCustomObject]@{ Name = "Delete"; IsEnabled = $false }
                CheckboxMyCreatedQueries = [PSCustomObject]@{ IsEnabled = $true; IsChecked = $false }
                CheckboxMyUpdatedQueries = [PSCustomObject]@{ IsEnabled = $false; IsChecked = $false }
            }
        }
        $Script:MainForm.Definition | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed++ }
        Mock Invoke-ElementClick { }
        Mock Set-TabResultOutputMode { }
        Mock Invoke-MainMenuTabAction { }
        Mock Get-MainMenuResultItem { @{ Copy = [PSCustomObject]@{ Name = "Copy"; IsEnabled = $true }; SelectAll = [PSCustomObject]@{ Name = "SelectAll"; IsEnabled = $false } } }
    }

    It 'Should click the active tab''s toolbar button' {
        Invoke-MainMenuAction -Tag "Button:ButtonSaveQuery"
        Should -Invoke Invoke-ElementClick -Times 1 -Exactly -ParameterFilter { $Element.Name -eq "Save" }
    }

    It 'Should not click a disabled or missing button (<Tag>)' -ForEach @(@{ Tag = "Button:ButtonDeleteQuery" }, @{ Tag = "Button:ButtonMissing" }) {
        Invoke-MainMenuAction -Tag $Tag
        Should -Invoke Invoke-ElementClick -Times 0 -Exactly
    }

    It 'Should toggle an enabled filter checkbox and leave a disabled one' {
        Invoke-MainMenuAction -Tag "Check:CheckboxMyCreatedQueries"
        $Script:MainForm.Elements.CheckboxMyCreatedQueries.IsChecked | Should -BeTrue
        Invoke-MainMenuAction -Tag "Check:CheckboxMyCreatedQueries"
        $Script:MainForm.Elements.CheckboxMyCreatedQueries.IsChecked | Should -BeFalse

        Invoke-MainMenuAction -Tag "Check:CheckboxMyUpdatedQueries"
        $Script:MainForm.Elements.CheckboxMyUpdatedQueries.IsChecked | Should -BeFalse
        { Invoke-MainMenuAction -Tag "Check:CheckboxMissing" } | Should -Not -Throw
    }

    It 'Should click the result context menu item only when enabled' {
        Invoke-MainMenuAction -Tag "Result:Copy"
        Invoke-MainMenuAction -Tag "Result:SelectAll"
        Invoke-MainMenuAction -Tag "Result:Missing"
        Should -Invoke Invoke-ElementClick -Times 1 -Exactly
        Should -Invoke Invoke-ElementClick -Times 1 -Exactly -ParameterFilter { $Element.Name -eq "Copy" }
    }

    It 'Should hand a tab command to Invoke-MainMenuTabAction' {
        Invoke-MainMenuAction -Tag "Tab:CloseOthers"
        Should -Invoke Invoke-MainMenuTabAction -Times 1 -Exactly -ParameterFilter { $Action -eq "CloseOthers" }
    }

    It 'Should switch the active tab''s results to <ExpectedMode>' -ForEach @(@{ ExpectedMode = "Grid" }, @{ ExpectedMode = "Text" }) {
        Invoke-MainMenuAction -Tag "Action:ResultsTo$ExpectedMode"
        Should -Invoke Set-TabResultOutputMode -Times 1 -Exactly -ParameterFilter { $Mode -eq $ExpectedMode -and $TabSession.TabId -eq "t1" }
    }

    It 'Should hand an application command to Invoke-MainMenuAppAction' {
        Mock Invoke-MainMenuAppAction { }
        Invoke-MainMenuAction -Tag "App:Help"
        Should -Invoke Invoke-MainMenuAppAction -Times 1 -Exactly -ParameterFilter { $Action -eq "Help" }
    }

    It 'Should close the main window for Exit' {
        Invoke-MainMenuAction -Tag "App:Exit"
        $Script:MainForm.Definition.Closed | Should -Be 1
        Should -Invoke Invoke-ElementClick -Times 0 -Exactly
    }
}

Describe 'Invoke-MainMenuAppAction' -Tag 'Unit' {
    BeforeEach {
        $Script:MainForm = [PSCustomObject]@{ Definition = [PSCustomObject]@{ Closed = 0 } }
        $Script:MainForm.Definition | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed++ }
        Mock Open-AboutForm { }
        Mock Open-HelpForm { }
        Mock Open-GitHubIssue { }
    }

    It 'Should show the About window, and not close the main window' {
        Invoke-MainMenuAppAction -Action About
        Should -Invoke Open-AboutForm -Times 1 -Exactly
        $Script:MainForm.Definition.Closed | Should -Be 0
    }

    It 'Should show the Help window' {
        Invoke-MainMenuAppAction -Action Help
        Should -Invoke Open-HelpForm -Times 1 -Exactly
    }

    It 'Should open a <Expected> issue on GitHub' -ForEach @(
        @{ Action = "ReportBug"; Expected = "Bug" }
        @{ Action = "RequestFeature"; Expected = "Feature" }
    ) {
        Invoke-MainMenuAppAction -Action $Action
        Should -Invoke Open-GitHubIssue -Times 1 -Exactly -ParameterFilter { $Kind -eq $Expected }
    }

    It 'Should close the main window for Exit' {
        Invoke-MainMenuAppAction -Action Exit
        $Script:MainForm.Definition.Closed | Should -Be 1
    }
}

Describe 'Invoke-MainMenuTabAction' -Tag 'Unit' {
    BeforeEach {
        $Script:ActiveTabId = "t1"
        Mock New-EmptyTabSession { "tab" }
        Mock Invoke-DuplicateTab { }
        Mock Select-AdjacentTab { }
        Mock Close-TabSession { }
        Mock Close-OtherTabSessions { }
        Mock Close-AllTabSessions { }
    }

    It 'Should open a new tab without output' {
        Invoke-MainMenuTabAction -Action New | Should -BeNullOrEmpty
        Should -Invoke New-EmptyTabSession -Times 1 -Exactly
    }

    It 'Should duplicate the active tab with and without its query' {
        Invoke-MainMenuTabAction -Action Duplicate
        Should -Invoke Invoke-DuplicateTab -Times 1 -Exactly -ParameterFilter { $TabId -eq "t1" -and -not $WithoutQuery }
        Invoke-MainMenuTabAction -Action DuplicateWithoutQuery
        Should -Invoke Invoke-DuplicateTab -Times 1 -Exactly -ParameterFilter { $TabId -eq "t1" -and $WithoutQuery }
    }

    It 'Should select the <Expected> tab' -ForEach @(@{ Expected = "Next" }, @{ Expected = "Previous" }) {
        Invoke-MainMenuTabAction -Action $Expected
        Should -Invoke Select-AdjacentTab -Times 1 -Exactly -ParameterFilter { $Direction -eq $Expected }
    }

    It 'Should close the active tab, the others, or all' {
        Invoke-MainMenuTabAction -Action Close
        Should -Invoke Close-TabSession -Times 1 -Exactly -ParameterFilter { $TabId -eq "t1" }
        Invoke-MainMenuTabAction -Action CloseOthers
        Should -Invoke Close-OtherTabSessions -Times 1 -Exactly -ParameterFilter { $KeepTabId -eq "t1" }
        Invoke-MainMenuTabAction -Action CloseAll
        Should -Invoke Close-AllTabSessions -Times 1 -Exactly
    }
}

Describe 'Get-MainMenuResultItem' -Tag 'Unit' {
    It 'Should collect the result context menu items by name' {
        $Script:DataGridQueryResultMenuItemCopy = "copy-item"
        $Script:DataGridQueryResultMenuItemViewSelected = "view-item"
        Remove-Variable -Scope Script -Name DataGridQueryResultMenuItemSaveAs -ErrorAction SilentlyContinue

        $Items = Get-MainMenuResultItem

        $Items.Keys.Count | Should -Be 9
        $Items.Copy | Should -BeExactly "copy-item"
        $Items.ViewSelected | Should -BeExactly "view-item"
        $Items.SaveAs | Should -BeNullOrEmpty
    }
}
