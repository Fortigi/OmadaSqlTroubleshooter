#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Open-SqlQueryInActiveTab.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$Message, $LogType)
        process { $script:Log += , [PSCustomObject]@{ Message = $Message; LogType = $LogType } }
    }
    function Get-ActiveTabSession { $script:ActiveTab }
    function Get-TabConnectionStatus { param($TabSession) }
    function Get-TabName { param($TabSession) "Tab A" }
    function Get-TabEditorText { param($TabSession) $TabSession.EditorText }
    function Resolve-QuerySavePrompt { param($QueryDoId, $EditorText, $IsDirty, $Connected) }
    function Request-TabQuerySave { param($TabSession, $Kind, [switch]$OpenQuery) }
    function Open-SqlQueryInTab { param($DoId, $DisplayName) }

    function New-TestList {
        param([string[]]$Content)
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Text in $Content) { $Items.Add([PSCustomObject]@{ Content = $Text }) }
        [PSCustomObject]@{ Items = $Items; SelectedItem = $null }
    }
}

Describe 'Open-SqlQueryInActiveTab' -Tag 'Unit' {
    BeforeEach {
        $script:Log = @()
        $script:ActiveTab = [PSCustomObject]@{ Id = "t1"; IsDirty = $true; DraftText = "SELECT draft"; EditorText = "SELECT 1"; AppConfig = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DoId = "10" } } }
        $Script:Tabs = @($script:ActiveTab)
        $Script:AppConfig = $script:ActiveTab.AppConfig
        Mock Get-TabConnectionStatus { $true }
        Mock Resolve-QuerySavePrompt { "SaveExisting" }
        Mock Request-TabQuerySave { "Saved" }
        Mock Open-SqlQueryInTab { "existing tab" }
        Mock Select-TabQueryListItem { }
    }

    It 'Should offer to save the active tab''s changes, then select the query in its list' {
        $Result = Open-SqlQueryInActiveTab -DoId "42" -DisplayName "Accounts"

        $Result | Should -Be $script:ActiveTab
        Should -Invoke Resolve-QuerySavePrompt -Times 1 -Exactly -ParameterFilter { $QueryDoId -eq "10" -and $EditorText -eq "SELECT 1" -and $IsDirty -eq $true -and $Connected -eq $true }
        Should -Invoke Request-TabQuerySave -Times 1 -Exactly -ParameterFilter { $Kind -eq "SaveExisting" -and $OpenQuery -and $TabSession.Id -eq "t1" }
        Should -Invoke Select-TabQueryListItem -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }
        $script:ActiveTab.IsDirty | Should -BeFalse
        $script:ActiveTab.DraftText | Should -BeNullOrEmpty
    }

    It 'Should not ask when there is nothing to save' {
        Mock Resolve-QuerySavePrompt { "None" }

        Open-SqlQueryInActiveTab -DoId "42" -DisplayName "Accounts" | Should -Be $script:ActiveTab

        Should -Invoke Request-TabQuerySave -Times 0 -Exactly
        Should -Invoke Select-TabQueryListItem -Times 1 -Exactly
    }

    It 'Should leave the tab as it is when the save prompt is cancelled' {
        Mock Request-TabQuerySave { "Cancel" }

        Open-SqlQueryInActiveTab -DoId "42" -DisplayName "Accounts" | Should -BeNullOrEmpty

        Should -Invoke Select-TabQueryListItem -Times 0 -Exactly
        $script:ActiveTab.IsDirty | Should -BeTrue
        $script:ActiveTab.DraftText | Should -Be "SELECT draft"
    }

    It 'Should select the tab that already holds the query instead of opening it twice' {
        $Holder = [PSCustomObject]@{ Id = "t2"; AppConfig = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DoId = "42" } } }
        $Script:Tabs = @($script:ActiveTab, $Holder)

        Open-SqlQueryInActiveTab -DoId "42" -DisplayName "Accounts" | Should -Be "existing tab"

        Should -Invoke Open-SqlQueryInTab -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }
        Should -Invoke Request-TabQuerySave -Times 0 -Exactly
        Should -Invoke Select-TabQueryListItem -Times 0 -Exactly
    }

    It 'Should warn and open nothing without an active tab' {
        $script:ActiveTab = $null
        $Script:Tabs = @()

        Open-SqlQueryInActiveTab -DoId "42" -DisplayName "Accounts" | Should -BeNullOrEmpty

        ($script:Log | Where-Object LogType -eq "WARNING").Message | Should -Match "no tab to open query 'Accounts'"
        Should -Invoke Select-TabQueryListItem -Times 0 -Exactly
    }

    It 'Should warn and open nothing in a tab that is not connected' {
        Mock Get-TabConnectionStatus { $false }

        Open-SqlQueryInActiveTab -DoId "42" -DisplayName "Accounts" | Should -BeNullOrEmpty

        ($script:Log | Where-Object LogType -eq "WARNING").Message | Should -Match "'Tab A' is not connected"
        Should -Invoke Resolve-QuerySavePrompt -Times 0 -Exactly
        Should -Invoke Select-TabQueryListItem -Times 0 -Exactly
        $script:ActiveTab.IsDirty | Should -BeTrue
    }
}

Describe 'Select-TabQueryListItem' -Tag 'Unit' {
    BeforeEach {
        Mock New-QueryListItem { [PSCustomObject]@{ Content = $Content; New = $true } }
    }

    It 'Should select the item of the query, matched on its id' {
        $List = New-TestList -Content @("Groups - 7", "Old name - 42", "Accounts - 142")
        $Script:MainForm = [PSCustomObject]@{ Elements = @{ ComboBoxSelectQuery = $List } }

        Select-TabQueryListItem -DoId "42" -DisplayName "Accounts"

        $List.SelectedItem.Content | Should -Be "Old name - 42"
        $List.Items.Count | Should -Be 3
        Should -Invoke New-QueryListItem -Times 0 -Exactly
    }

    It 'Should add the query when the list does not show it, and select it' {
        $List = New-TestList -Content @("Groups - 7")
        $Script:MainForm = [PSCustomObject]@{ Elements = @{ ComboBoxSelectQuery = $List } }

        Select-TabQueryListItem -DoId "42" -DisplayName "Accounts"

        $List.Items.Count | Should -Be 2
        $List.SelectedItem.Content | Should -Be "Accounts - 42"
        $List.SelectedItem.New | Should -BeTrue
    }
}
