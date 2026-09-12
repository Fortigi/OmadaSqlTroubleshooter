#Requires -Version 7.0
# Tests for the strict boolean resolution introduced in review of PR #106.
#
# PowerShell's [bool] cast is truthiness, not parsing: every non-empty string is $true, so
# [bool]'False' is True and [bool]'0' is True. That is the same silent inversion issue #103 exists
# to fix, and it would have reappeared in the fix itself in three places - the two literal
# formatters and the settings resolver.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Resolve-StrictBoolean.ps1")
}

Describe "Resolve-StrictBoolean" {

    Context "The PowerShell cast this function exists to replace" {
        It "is demonstrably wrong for <Name>, which is why a cast is not used anywhere" -ForEach @(
            @{ Name = "the string False"; Value = "False" }
            @{ Name = "the string false"; Value = "false" }
            @{ Name = "the string 0"; Value = "0" }
        ) {
            # Guard rather than documentation: if PowerShell ever changed this, the reasoning in
            # these functions would need revisiting.
            [bool]$Value | Should -BeTrue -Because "the plain cast is truthiness, not parsing"
        }
    }

    Context "Real booleans" {
        It "resolves `$true and `$false" {
            Resolve-StrictBoolean -Value $true | Should -BeTrue
            Resolve-StrictBoolean -Value $false | Should -BeFalse
        }
    }

    Context "Strings that genuinely parse" {
        It "resolves <Value> to <Expected>" -ForEach @(
            @{ Value = "true"; Expected = $true }
            @{ Value = "True"; Expected = $true }
            @{ Value = "TRUE"; Expected = $true }
            @{ Value = "false"; Expected = $false }
            @{ Value = "False"; Expected = $false }
            @{ Value = "FALSE"; Expected = $false }
            @{ Value = "  false  "; Expected = $false }
        ) {
            Resolve-StrictBoolean -Value $Value | Should -Be $Expected
        }
    }

    Context "Numbers, which is how a bit value arrives when carried as 0/1" {
        It "resolves <Value> to <Expected>" -ForEach @(
            @{ Value = 0; Expected = $false }
            @{ Value = 1; Expected = $true }
            @{ Value = [int64]0; Expected = $false }
            @{ Value = -1; Expected = $true }
            @{ Value = 0d; Expected = $false }
        ) {
            Resolve-StrictBoolean -Value $Value | Should -Be $Expected
        }
    }

    Context "Everything it cannot vouch for resolves to null, so the caller can fall back" {
        It "returns null for a <Name>, which is not a truth value" -ForEach @(
            @{ Name = "double"; Value = [double]1 }
            @{ Name = "double zero"; Value = [double]0 }
            @{ Name = "single"; Value = [single]1 }
        ) {
            # Deliberate, and pinned so the documented accepted types stay true: 1e-300 is not
            # meaningfully "true" and rounding would decide the answer. Nothing produces a bit as a
            # float, so accepting one would only widen the guess this function exists to refuse.
            Resolve-StrictBoolean -Value $Value | Should -BeNullOrEmpty
        }

        It "returns null for <Name>" -ForEach @(
            @{ Name = "null"; Value = $null }
            @{ Name = "DBNull"; Value = [System.DBNull]::Value }
            @{ Name = "the empty string"; Value = "" }
            @{ Name = "whitespace"; Value = "   " }
            @{ Name = "arbitrary text"; Value = "maybe" }
            @{ Name = "the string yes"; Value = "yes" }
            @{ Name = "the string 1 as text"; Value = "1" }
            @{ Name = "a date"; Value = [datetime]"2019-11-20" }
            @{ Name = "a guid"; Value = [guid]::Empty }
        ) {
            Resolve-StrictBoolean -Value $Value | Should -BeNullOrEmpty
        }

        It "distinguishes a null result from a `$false result" {
            # Both are falsy, so the distinction has to be made on null-ness, which is exactly what
            # every call site relies on.
            $null -eq (Resolve-StrictBoolean -Value "maybe") | Should -BeTrue
            $null -eq (Resolve-StrictBoolean -Value $false) | Should -BeFalse
        }
    }

    Context "Culture independence" {
        It "parses the same under tr-TR, where case folding of 'true' does not behave" {
            $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo("tr-TR")
                Resolve-StrictBoolean -Value "TRUE" | Should -BeTrue
                Resolve-StrictBoolean -Value "FALSE" | Should -BeFalse
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $Original
            }
        }
    }
}
