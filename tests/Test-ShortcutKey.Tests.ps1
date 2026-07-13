BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-ShortcutKey.ps1"
    . $Command
}

Describe 'Test-ShortcutKey' {
    Context 'ordinary typing must never be treated as a shortcut (password-leak guard)' {
        It 'returns false for a bare letter' {
            Test-ShortcutKey -KeyName "P" | Should -BeFalse
        }

        It 'returns false for a bare digit' {
            Test-ShortcutKey -KeyName "D4" | Should -BeFalse
        }

        It 'returns false for Shift+letter (capitalisation, not a shortcut)' {
            Test-ShortcutKey -KeyName "P" -ModifierNames "Shift" | Should -BeFalse
        }

        It 'returns false for a bare Shift key (would leak the capitalisation pattern)' {
            Test-ShortcutKey -KeyName "LeftShift" | Should -BeFalse
            Test-ShortcutKey -KeyName "RightShift" | Should -BeFalse
        }

        It 'returns false for bare navigation/editing keys' {
            Test-ShortcutKey -KeyName "Enter" | Should -BeFalse
            Test-ShortcutKey -KeyName "Back" | Should -BeFalse
            Test-ShortcutKey -KeyName "Space" | Should -BeFalse
        }

        It 'does not misread a normal key name that contains an f' {
            Test-ShortcutKey -KeyName "OemComma" | Should -BeFalse
        }
    }

    Context 'genuine shortcuts are recorded' {
        It 'returns true for a Ctrl chord (e.g. Ctrl+S)' {
            Test-ShortcutKey -KeyName "S" -ModifierNames "Control" | Should -BeTrue
        }

        It 'returns true for a Ctrl+Shift chord (e.g. Ctrl+Shift+K)' {
            Test-ShortcutKey -KeyName "K" -ModifierNames "Control, Shift" | Should -BeTrue
        }

        It 'returns true for an Alt chord (e.g. Alt+F4)' {
            Test-ShortcutKey -KeyName "F4" -ModifierNames "Alt" | Should -BeTrue
        }

        It 'returns true for function keys even without a modifier (F1 through F24)' {
            Test-ShortcutKey -KeyName "F1" | Should -BeTrue
            Test-ShortcutKey -KeyName "F5" | Should -BeTrue
            Test-ShortcutKey -KeyName "F24" | Should -BeTrue
        }

        It 'returns true for the Ctrl modifier keys themselves' {
            Test-ShortcutKey -KeyName "LeftCtrl" | Should -BeTrue
            Test-ShortcutKey -KeyName "RightCtrl" | Should -BeTrue
        }

        It 'returns true for the Alt and Windows modifier keys themselves' {
            Test-ShortcutKey -KeyName "LeftAlt" | Should -BeTrue
            Test-ShortcutKey -KeyName "LWin" | Should -BeTrue
        }
    }
}
