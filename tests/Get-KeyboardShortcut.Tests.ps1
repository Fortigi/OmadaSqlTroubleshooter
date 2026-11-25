#Requires -Version 7.0
BeforeDiscovery {
    . ([System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private", "Get-KeyboardShortcut.ps1"))
    $Script:MenuShortcuts = @(Get-KeyboardShortcut | Where-Object { $_.Tag } | ForEach-Object { @{ Gesture = $_.Gesture; ShortcutTag = $_.Tag } })
}

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($Script:RepositoryRoot, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Get-KeyboardShortcut.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { } }
    function Invoke-MainMenuAction { param($Tag) }

    [xml]$Script:MainFormXaml = Get-Content -Path ([System.IO.Path]::Combine($Script:RepositoryRoot, "src", "Lib", "ui", "MainForm.xaml")) -Raw
    $Script:MenuItems = @($Script:MainFormXaml.SelectNodes("//*[local-name()='MenuItem' and @Tag]") | ForEach-Object {
            [PSCustomObject]@{ Tag = $_.GetAttribute("Tag"); Gesture = $_.GetAttribute("InputGestureText") }
        })

    function script:New-KeyEvent {
        param([string]$Key, [string]$Modifiers = "None", [bool]$IsRepeat = $false, [bool]$Handled = $false)
        [PSCustomObject]@{ Key = $Key; KeyboardDevice = [PSCustomObject]@{ Modifiers = $Modifiers }; IsRepeat = $IsRepeat; Handled = $Handled }
    }
}

Describe 'Get-KeyboardShortcut' -Tag 'Unit' {
    BeforeAll {
        $Script:Shortcuts = @(Get-KeyboardShortcut)
    }

    It 'Should list each gesture once' {
        @($Script:Shortcuts.Gesture | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }

    It 'Should give every entry a description, a known handler and a place where it works' {
        foreach ($Shortcut in $Script:Shortcuts) {
            $Shortcut.Description | Should -Not -BeNullOrEmpty
            $Shortcut.Where | Should -Not -BeNullOrEmpty
            $Shortcut.Handler | Should -BeIn @("Shortcut", "Window")
        }
    }

    It 'Should give the shortcuts it runs itself a key and a menu command' {
        foreach ($Shortcut in @($Script:Shortcuts | Where-Object Handler -eq "Shortcut")) {
            $Shortcut.Key | Should -Not -BeNullOrEmpty
            $Shortcut.Tag | Should -Not -BeNullOrEmpty
        }
    }

    It 'Should name only menu commands that are on the menu bar' {
        foreach ($Tag in @($Script:Shortcuts.Tag | Where-Object { $_ })) {
            $Tag | Should -BeIn $Script:MenuItems.Tag
        }
    }

    It 'Should show the same gesture on the menu as it lists (<Gesture>)' -ForEach $Script:MenuShortcuts {
        ($Script:MenuItems | Where-Object Tag -eq $ShortcutTag).Gesture | Should -Be $Gesture
    }

    It 'Should list every gesture the menu bar shows' {
        foreach ($Item in @($Script:MenuItems | Where-Object Gesture)) {
            $Item.Gesture | Should -BeIn $Script:Shortcuts.Gesture
        }
    }

    It 'Should have the shortcuts that were asked for: File > New, Results > Export, Window > New tab' {
        ($Script:Shortcuts | Where-Object Tag -eq "Button:ButtonNewQuery").Gesture | Should -Be "Ctrl+N"
        ($Script:Shortcuts | Where-Object Tag -eq "Button:ButtonSaveOutputFile").Gesture | Should -Be "Ctrl+Shift+E"
        ($Script:Shortcuts | Where-Object Tag -eq "Tab:New").Gesture | Should -Be "Ctrl+Shift+N"
    }
}

Describe 'Resolve-KeyboardShortcut' -Tag 'Unit' {
    It 'Should run <Expected> for <Key> with <Modifiers>' -ForEach @(
        @{ Key = "N"; Modifiers = "Control"; Expected = "Button:ButtonNewQuery" }
        @{ Key = "N"; Modifiers = "Control, Shift"; Expected = "Tab:New" }
        @{ Key = "N"; Modifiers = "Shift, Control"; Expected = "Tab:New" }
        @{ Key = "E"; Modifiers = "Control, Shift"; Expected = "Button:ButtonSaveOutputFile" }
    ) {
        Resolve-KeyboardShortcut -KeyName $Key -ModifierNames $Modifiers | Should -Be $Expected
    }

    It 'Should run nothing for <Key> with <Modifiers>' -ForEach @(
        @{ Key = "N"; Modifiers = "None" }
        @{ Key = "N"; Modifiers = "" }
        @{ Key = "N"; Modifiers = "Control, Alt" }
        @{ Key = "E"; Modifiers = "Control" }
        @{ Key = "S"; Modifiers = "Control" }
        @{ Key = "F5"; Modifiers = "None" }
        @{ Key = ""; Modifiers = "Control" }
    ) {
        Resolve-KeyboardShortcut -KeyName $Key -ModifierNames $Modifiers | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-ModifierSet' -Tag 'Unit' {
    It 'Should give <Expected> for "<Names>"' -ForEach @(
        @{ Names = "Shift, Control"; Expected = "Control,Shift" }
        @{ Names = "Control,Shift"; Expected = "Control,Shift" }
        @{ Names = "None"; Expected = "" }
        @{ Names = ""; Expected = "" }
        @{ Names = "Alt"; Expected = "Alt" }
    ) {
        ConvertTo-ModifierSet -ModifierNames $Names | Should -BeExactly $Expected
    }
}

Describe 'Invoke-KeyboardShortcut' -Tag 'Unit' {
    BeforeEach {
        Mock Invoke-MainMenuAction { }
    }

    It 'Should run the menu command and mark the key handled' {
        $KeyEvent = New-KeyEvent -Key "N" -Modifiers "Control, Shift"

        Invoke-KeyboardShortcut -KeyEventArgs $KeyEvent

        $KeyEvent.Handled | Should -BeTrue
        Should -Invoke Invoke-MainMenuAction -Times 1 -Exactly -ParameterFilter { $Tag -eq "Tab:New" }
    }

    It 'Should leave a key alone that is not one of them' {
        $KeyEvent = New-KeyEvent -Key "S" -Modifiers "Control"

        Invoke-KeyboardShortcut -KeyEventArgs $KeyEvent

        $KeyEvent.Handled | Should -BeFalse
        Should -Invoke Invoke-MainMenuAction -Times 0 -Exactly
    }

    It 'Should ignore <Case>' -ForEach @(
        @{ Case = 'a held key repeating'; IsRepeat = $true; Handled = $false }
        @{ Case = 'a key another handler took'; IsRepeat = $false; Handled = $true }
    ) {
        Invoke-KeyboardShortcut -KeyEventArgs (New-KeyEvent -Key "N" -Modifiers "Control" -IsRepeat $IsRepeat -Handled $Handled)

        Should -Invoke Invoke-MainMenuAction -Times 0 -Exactly
    }
}
