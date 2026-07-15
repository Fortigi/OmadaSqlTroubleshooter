BeforeAll {
    . $PSScriptRoot\..\src\Lib\Functions\Private\Test-EditorNavigationKey.ps1
}

Describe "Test-EditorNavigationKey" {
    Context "keys WPF's TabControl claims for first/last-tab navigation" {
        # Key names are passed as [System.Windows.Input.Key] names (what .ToString() yields) rather
        # than the WPF types, so this suite runs headless without PresentationCore.
        It "returns true for Home (TabControl would jump to the first tab)" {
            Test-EditorNavigationKey -KeyName "Home" | Should -BeTrue
        }

        It "returns true for End (TabControl would jump to the last tab)" {
            Test-EditorNavigationKey -KeyName "End" | Should -BeTrue
        }

        It "is case-insensitive on the key name" {
            Test-EditorNavigationKey -KeyName "home" | Should -BeTrue
            Test-EditorNavigationKey -KeyName "END" | Should -BeTrue
        }

        It "trims surrounding whitespace" {
            Test-EditorNavigationKey -KeyName " Home " | Should -BeTrue
        }
    }

    Context "keys the TabControl does not claim must not be intercepted" {
        # Verified empirically against a real WPF TabControl: only Home and End are stolen. Anything
        # else listed here must keep flowing normally, so the editor and grid behave as usual.
        It "returns false for <_>" -ForEach @(
            "PageUp", "PageDown", "Up", "Down", "Left", "Right",
            "Tab", "Back", "Delete", "Enter", "Escape", "Space", "A", "S", "F5"
        ) {
            Test-EditorNavigationKey -KeyName $_ | Should -BeFalse
        }
    }

    Context "defensive input" {
        It "returns false for an empty key name" {
            Test-EditorNavigationKey -KeyName "" | Should -BeFalse
        }

        It "returns false for whitespace" {
            Test-EditorNavigationKey -KeyName "   " | Should -BeFalse
        }

        It "returns false when no key name is supplied at all" {
            Test-EditorNavigationKey | Should -BeFalse
        }

        It "does not match a key whose name merely contains Home or End" {
            Test-EditorNavigationKey -KeyName "HomePage" | Should -BeFalse
            Test-EditorNavigationKey -KeyName "Append" | Should -BeFalse
        }
    }
}
