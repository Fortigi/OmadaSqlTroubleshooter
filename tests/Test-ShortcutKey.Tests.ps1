BeforeAll {
    # The Key/ModifierKeys enums live in PresentationCore (WPF). CI runs on windows-latest, so the
    # Windows Desktop assemblies are available.
    Add-Type -AssemblyName PresentationCore

    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-ShortcutKey.ps1"
    . $Command
}

Describe 'Test-ShortcutKey' {
    Context 'ordinary typing must never be treated as a shortcut (password-leak guard)' {
        It 'returns false for a bare letter' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::P) | Should -BeFalse
        }

        It 'returns false for a bare digit' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::D4) | Should -BeFalse
        }

        It 'returns false for Shift+letter (capitalisation, not a shortcut)' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::P) -Modifiers ([System.Windows.Input.ModifierKeys]::Shift) | Should -BeFalse
        }

        It 'returns false for a bare Shift key (would leak the capitalisation pattern)' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::LeftShift) | Should -BeFalse
        }

        It 'returns false for bare navigation/editing keys' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::Enter) | Should -BeFalse
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::Back) | Should -BeFalse
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::Space) | Should -BeFalse
        }
    }

    Context 'genuine shortcuts are recorded' {
        It 'returns true for a Ctrl chord (e.g. Ctrl+S)' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::S) -Modifiers ([System.Windows.Input.ModifierKeys]::Control) | Should -BeTrue
        }

        It 'returns true for a Ctrl+Shift chord (e.g. Ctrl+Shift+K)' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::K) -Modifiers ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift) | Should -BeTrue
        }

        It 'returns true for an Alt chord (e.g. Alt+F4)' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::F4) -Modifiers ([System.Windows.Input.ModifierKeys]::Alt) | Should -BeTrue
        }

        It 'returns true for function keys even without a modifier (e.g. F5)' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::F5) | Should -BeTrue
        }

        It 'returns true for the Ctrl modifier keys themselves' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::LeftCtrl) | Should -BeTrue
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::RightCtrl) | Should -BeTrue
        }

        It 'returns true for the Alt and Windows modifier keys themselves' {
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::LeftAlt) | Should -BeTrue
            Test-ShortcutKey -Key ([System.Windows.Input.Key]::LWin) | Should -BeTrue
        }
    }
}
