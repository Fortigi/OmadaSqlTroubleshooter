#Requires -Version 7.0
# Tests for the PowerShell literal formatting of issue #103.
#
# The round-trip assertions matter more here than the exact text does: a PowerShell literal that
# parses but rehydrates to the wrong TYPE is the failure this change exists to prevent. The
# clearest case is the boolean - the pre-#103 code copied a bit column as the string 'False', and a
# non-empty string is truthy in PowerShell, so the pasted script silently evaluates the opposite of
# what the grid showed.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-QueryResultValueKind.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SqlLiteral.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-PowerShellLiteral.ps1")

    function Invoke-Literal {
        <#
            Parses the literal with the PowerShell language parser and evaluates it, so the test
            asserts what the user would actually get after pasting rather than what the text looks
            like.
        #>
        param(
            [string]$Literal
        )

        return (& ([ScriptBlock]::Create($Literal)))
    }

    function Invoke-InEveryCulture {
        param(
            [scriptblock]$Action
        )

        $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
        $Result = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($CultureName in @("nl-NL", "en-US", "tr-TR")) {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($CultureName)
                $Result.Add([string](& $Action))
            }
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $Original
        }

        @($Result | Select-Object -Unique).Count | Should -Be 1 -Because "the output must not depend on the thread culture"
        return $Result[0]
    }
}

Describe "ConvertTo-PowerShellLiteral" {

    Context "The mapping table from issue #103" {
        It "formats <Name> as <Expected>" -ForEach @(
            @{ Name = "an int"; Value = [int]900; Expected = "900" }
            @{ Name = "a bigint"; Value = [int64]::MaxValue; Expected = "9223372036854775807" }
            @{ Name = "a negative int"; Value = [int]-42; Expected = "-42" }
            @{ Name = "a double"; Value = [double]1.5; Expected = "1.5" }
            @{ Name = "bit true"; Value = $true; Expected = "`$true" }
            @{ Name = "bit false"; Value = $false; Expected = "`$false" }
            @{ Name = "NULL"; Value = $null; Expected = "`$null" }
            @{ Name = "an ASCII string"; Value = "IDG-900"; Expected = "'IDG-900'" }
            @{ Name = "a leading-zero code"; Value = "007"; Expected = "'007'" }
            @{ Name = "an all-digit string"; Value = "12345"; Expected = "'12345'" }
            @{ Name = "a non-ASCII string"; Value = "Müller"; Expected = "'Müller'" }
            @{ Name = "the empty string"; Value = ""; Expected = "''" }
            @{ Name = "empty varbinary"; Value = [byte[]]@(); Expected = "[byte[]]@()" }
        ) {
            ConvertTo-PowerShellLiteral -Value $Value -TypedLiteral | Should -BeExactly $Expected
        }

        It "emits a typed literal for <Name>" -ForEach @(
            @{ Name = "a decimal"; Value = 12.50d; Expected = "[decimal]'12.50'" }
            @{ Name = "a datetime"; Value = [datetime]"2019-11-20T13:55:09"; Expected = "[datetime]'2019-11-20T13:55:09.000'" }
            @{ Name = "a datetimeoffset"; Value = [datetimeoffset]"2019-11-20T13:55:09+01:00"; Expected = "[datetimeoffset]'2019-11-20T13:55:09.0000000+01:00'" }
            @{ Name = "a time"; Value = [timespan]"13:55:09"; Expected = "[timespan]'13:55:09.0000000'" }
            @{ Name = "a GUID"; Value = [guid]"0f6a1b3c-1111-4a2b-9c01-a00000000900"; Expected = "[guid]'0f6a1b3c-1111-4a2b-9c01-a00000000900'" }
            @{ Name = "varbinary"; Value = [byte[]]@(10, 27, 44); Expected = "[byte[]]@(0x0A, 0x1B, 0x2C)" }
        ) {
            ConvertTo-PowerShellLiteral -Value $Value -TypedLiteral | Should -BeExactly $Expected
        }

        It "emits a plain quoted string for <Name> when typed literals are off" -ForEach @(
            @{ Name = "a datetime"; Value = [datetime]"2019-11-20T13:55:09"; Expected = "'2019-11-20T13:55:09.000'" }
            @{ Name = "a GUID"; Value = [guid]"0f6a1b3c-1111-4a2b-9c01-a00000000900"; Expected = "'0f6a1b3c-1111-4a2b-9c01-a00000000900'" }
            @{ Name = "a time"; Value = [timespan]"13:55:09"; Expected = "'13:55:09.0000000'" }
            @{ Name = "a decimal"; Value = 12.50d; Expected = "12.50" }
        ) {
            ConvertTo-PowerShellLiteral -Value $Value | Should -BeExactly $Expected
        }
    }

    Context "Escaping" {
        It "escapes <Name>" -ForEach @(
            @{ Name = "an apostrophe"; Value = "O'Brien"; Expected = "'O''Brien'" }
            @{ Name = "a lone quote"; Value = "'"; Expected = "''''" }
            @{ Name = "a doubled quote"; Value = "''"; Expected = "''''''" }
            @{ Name = "a comment sequence"; Value = "x'); DROP TABLE t; --"; Expected = "'x''); DROP TABLE t; --'" }
            @{ Name = "a closing bracket"; Value = "a]b"; Expected = "'a]b'" }
        ) {
            ConvertTo-PowerShellLiteral -Value $Value | Should -BeExactly $Expected
        }

        It "does not expand a value that looks like a variable, because the literal is single quoted" {
            $Literal = ConvertTo-PowerShellLiteral -Value '$PSVersionTable'
            $Literal | Should -BeExactly "'`$PSVersionTable'"
            Invoke-Literal -Literal $Literal | Should -BeExactly '$PSVersionTable'
        }

        It "does not execute a subexpression embedded in a value" {
            $Literal = ConvertTo-PowerShellLiteral -Value '$(Write-Host pwned)'
            Invoke-Literal -Literal $Literal | Should -BeExactly '$(Write-Host pwned)'
        }

        It "keeps a backtick literal" {
            $Value = 'a`nb'
            Invoke-Literal -Literal (ConvertTo-PowerShellLiteral -Value $Value) | Should -BeExactly $Value
        }
    }

    Context "A Boolean kind holding text is never guessed at (review of PR #106)" {
        It "emits `$false for the string 'False' rather than `$true" {
            # [bool]'False' is $true, so a plain cast would emit $true here. In PowerShell that is
            # doubly bad: the pasted script would then take the opposite branch with no error.
            ConvertTo-PowerShellLiteral -Value "False" -SqlType "bit" | Should -BeExactly "`$false"
        }

        It "emits `$true for the string 'True'" {
            ConvertTo-PowerShellLiteral -Value "True" -SqlType "bit" | Should -BeExactly "`$true"
        }

        It "falls back to a quoted literal for a bit column holding something that is not a boolean" {
            ConvertTo-PowerShellLiteral -Value "maybe" -SqlType "bit" | Should -BeExactly "'maybe'"
        }

        It "round-trips the string 'False' to a `$false that is actually falsy" {
            $RoundTrip = Invoke-Literal -Literal (ConvertTo-PowerShellLiteral -Value "False" -SqlType "bit")
            $RoundTrip | Should -BeOfType [bool]
            if ($RoundTrip) { throw "a bit column holding 'False' must not evaluate as true" }
        }
    }

    Context "Round trip - the literal rehydrates to the original typed value" {
        It "round-trips <Name>" -ForEach @(
            @{ Name = "an int"; Value = [int]900 }
            @{ Name = "Int64.MaxValue"; Value = [int64]::MaxValue }
            @{ Name = "a decimal"; Value = 12.50d }
            @{ Name = "a double"; Value = [double]1.5 }
            @{ Name = "bit true"; Value = $true }
            @{ Name = "bit false"; Value = $false }
            @{ Name = "a datetime"; Value = [datetime]"2019-11-20T13:55:09" }
            @{ Name = "a GUID"; Value = [guid]"0f6a1b3c-1111-4a2b-9c01-a00000000900" }
            @{ Name = "a time"; Value = [timespan]"13:55:09" }
            @{ Name = "a leading-zero code"; Value = "007" }
            @{ Name = "an apostrophe"; Value = "O'Brien" }
            @{ Name = "a non-ASCII value"; Value = "Müller" }
            @{ Name = "an embedded CRLF"; Value = "a`r`nb" }
            @{ Name = "a tab"; Value = "a`tb" }
        ) {
            Invoke-Literal -Literal (ConvertTo-PowerShellLiteral -Value $Value -TypedLiteral) | Should -Be $Value
        }

        It "round-trips `$null" {
            Invoke-Literal -Literal (ConvertTo-PowerShellLiteral -Value $null) | Should -BeNullOrEmpty
        }

        It "round-trips varbinary to the same bytes" {
            $Value = [byte[]]@(10, 27, 44)
            $RoundTrip = Invoke-Literal -Literal (ConvertTo-PowerShellLiteral -Value $Value -TypedLiteral)
            [System.Linq.Enumerable]::SequenceEqual([byte[]]$RoundTrip, $Value) | Should -BeTrue
        }

        It "round-trips a bit to a Boolean and not to a truthy string - the #103 case 4 guard" {
            # 'False' is a non-empty string, so it is TRUE in PowerShell. Copying a bit column as
            # text inverts the test in the pasted script without any error at all.
            $Literal = ConvertTo-PowerShellLiteral -Value $false
            $RoundTrip = Invoke-Literal -Literal $Literal

            $RoundTrip | Should -BeOfType [bool]
            $RoundTrip | Should -BeFalse
            if ($RoundTrip) { throw "a copied 'false' must not evaluate as true" }
        }

        It "round-trips a decimal as a decimal rather than as a double" {
            $RoundTrip = Invoke-Literal -Literal (ConvertTo-PowerShellLiteral -Value 12.50d -TypedLiteral)
            $RoundTrip | Should -BeOfType [decimal]
        }
    }

    Context "Culture independence" {
        It "renders <Name> identically under nl-NL, en-US and tr-TR" -ForEach @(
            @{ Name = "a decimal"; Value = 12.50d; Expected = "[decimal]'12.50'" }
            @{ Name = "a double"; Value = [double]1234.5; Expected = "1234.5" }
            @{ Name = "a datetime"; Value = [datetime]"2019-11-20T13:55:09"; Expected = "[datetime]'2019-11-20T13:55:09.000'" }
            @{ Name = "a time"; Value = [timespan]"13:55:09"; Expected = "[timespan]'13:55:09.0000000'" }
            @{ Name = "a bit"; Value = $false; Expected = "`$false" }
            @{ Name = "an ISO timestamp arriving as a string"; Value = "2019-11-20T13:55:09"; Expected = "[datetime]'2019-11-20T13:55:09.000'" }
        ) {
            $Actual = Invoke-InEveryCulture -Action { ConvertTo-PowerShellLiteral -Value $Value -TypedLiteral }
            $Actual | Should -BeExactly $Expected
        }
    }
}
