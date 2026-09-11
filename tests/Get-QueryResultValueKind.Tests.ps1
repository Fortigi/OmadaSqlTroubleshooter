#Requires -Version 7.0
# Tests for the type resolution behind issue #103's "Copy as SQL/PowerShell array".
#
# The point of these assertions is the NEGATIVE ones: a string that looks like a number must stay a
# string. The pre-#103 behaviour resolved types by matching the rendered text against "^-?\d+$",
# which is exactly what turns the code "007" into 7 and compares an nvarchar column as an int.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Get-QueryResultValueKind.ps1")
}

Describe "Get-QueryResultValueKind" {

    Context "Missing values" {
        It "resolves `$null to Null" {
            Get-QueryResultValueKind -Value $null | Should -Be "Null"
        }

        It "resolves DBNull to Null" {
            Get-QueryResultValueKind -Value ([System.DBNull]::Value) | Should -Be "Null"
        }
    }

    Context "CLR type - priority 2" {
        It "resolves <Name> to <Expected>" -ForEach @(
            @{ Name = "Int32"; Value = [int]900; Expected = "Integer" }
            @{ Name = "Int64"; Value = [int64]::MaxValue; Expected = "Integer" }
            @{ Name = "Int16"; Value = [int16]7; Expected = "Integer" }
            @{ Name = "Byte"; Value = [byte]255; Expected = "Integer" }
            @{ Name = "Boolean true"; Value = $true; Expected = "Boolean" }
            @{ Name = "Boolean false"; Value = $false; Expected = "Boolean" }
            @{ Name = "Decimal"; Value = 12.50d; Expected = "Decimal" }
            @{ Name = "Double"; Value = [double]1.5; Expected = "Float" }
            @{ Name = "DateTime"; Value = [datetime]"2019-11-20T13:55:09"; Expected = "DateTime" }
            @{ Name = "DateTimeOffset"; Value = [datetimeoffset]"2019-11-20T13:55:09+01:00"; Expected = "DateTimeOffset" }
            @{ Name = "TimeSpan"; Value = [timespan]"13:55:09"; Expected = "Time" }
            @{ Name = "Guid"; Value = [guid]"0f6a1b3c-1111-4a2b-9c01-a00000000900"; Expected = "Guid" }
            @{ Name = "Byte array"; Value = [byte[]]@(10, 27); Expected = "Binary" }
            @{ Name = "String"; Value = "IDG-900"; Expected = "String" }
        ) {
            Get-QueryResultValueKind -Value $Value | Should -Be $Expected
        }

        It "resolves the properties of a real ConvertFrom-Json row, which is how result rows arrive" {
            # This is the actual shape the copy path sees: the SqlDataProducer response, round
            # tripped through ConvertFrom-Json. It is what makes priority 2 work at all, so it is
            # asserted against the real deserialiser rather than against hand-built values.
            $Row = '{ "Id": 900, "Number": "IDG-900", "Deleted": false, "ParentID": null, "Huge": 12345678901234567890 }' | ConvertFrom-Json

            Get-QueryResultValueKind -Value $Row.Id | Should -Be "Integer"
            Get-QueryResultValueKind -Value $Row.Number | Should -Be "String"
            Get-QueryResultValueKind -Value $Row.Deleted | Should -Be "Boolean"
            Get-QueryResultValueKind -Value $Row.ParentID | Should -Be "Null"
            Get-QueryResultValueKind -Value $Row.Huge | Should -Be "Integer"
        }
    }

    Context "A string is never promoted to a number - the #103 regression guard" {
        It "keeps <Name> a String" -ForEach @(
            @{ Name = "leading zeros"; Value = "007" }
            @{ Name = "all digits"; Value = "12345" }
            @{ Name = "negative digits"; Value = "-42" }
            @{ Name = "a decimal-looking string"; Value = "12.50" }
            @{ Name = "a date without a time"; Value = "2019-01-01" }
            @{ Name = "a time on its own"; Value = "13:55:09" }
            @{ Name = "text"; Value = "IDG-900" }
            @{ Name = "the empty string"; Value = "" }
            @{ Name = "True as text"; Value = "True" }
        ) {
            Get-QueryResultValueKind -Value $Value | Should -Be "String"
        }
    }

    Context "String refinement - priority 3" {
        It "refines <Name> to <Expected>" -ForEach @(
            @{ Name = "an ISO timestamp"; Value = "2019-11-20T13:55:09"; Expected = "DateTime" }
            @{ Name = "an ISO timestamp with a space"; Value = "2019-11-20 13:55:09"; Expected = "DateTime" }
            @{ Name = "an ISO timestamp with fractions"; Value = "2019-11-20T13:55:09.1234567"; Expected = "DateTime" }
            @{ Name = "an offset timestamp"; Value = "2019-11-20T13:55:09+01:00"; Expected = "DateTimeOffset" }
            @{ Name = "a Zulu timestamp"; Value = "2019-11-20T13:55:09Z"; Expected = "DateTimeOffset" }
            @{ Name = "a canonical GUID"; Value = "0f6a1b3c-1111-4a2b-9c01-a00000000900"; Expected = "Guid" }
        ) {
            Get-QueryResultValueKind -Value $Value | Should -Be $Expected
        }

        It "does not refine a GUID that is not in the canonical form" {
            Get-QueryResultValueKind -Value "{0f6a1b3c-1111-4a2b-9c01-a00000000900}" | Should -Be "String"
        }

        It "does not refine a timestamp that is not a real date" {
            Get-QueryResultValueKind -Value "2019-13-45T99:99:99" | Should -Be "String"
        }

        It "skips refinement entirely when asked to" {
            Get-QueryResultValueKind -Value "2019-11-20T13:55:09" -SkipValueRefinement | Should -Be "String"
        }
    }

    Context "Declared SQL type - priority 1" {
        It "maps <SqlType> to <Expected>" -ForEach @(
            @{ SqlType = "bit"; Expected = "Boolean" }
            @{ SqlType = "int"; Expected = "Integer" }
            @{ SqlType = "bigint"; Expected = "Integer" }
            @{ SqlType = "tinyint"; Expected = "Integer" }
            @{ SqlType = "decimal(18,2)"; Expected = "Decimal" }
            @{ SqlType = "money"; Expected = "Decimal" }
            @{ SqlType = "float"; Expected = "Float" }
            @{ SqlType = "datetime2(7)"; Expected = "DateTime" }
            @{ SqlType = "datetimeoffset"; Expected = "DateTimeOffset" }
            @{ SqlType = "time(7)"; Expected = "Time" }
            @{ SqlType = "uniqueidentifier"; Expected = "Guid" }
            @{ SqlType = "varbinary(max)"; Expected = "Binary" }
            @{ SqlType = "nvarchar(50) NOT NULL"; Expected = "String" }
        ) {
            Get-SqlTypeNameKind -SqlType $SqlType | Should -Be $Expected
        }

        It "returns `$null for a type it does not know" {
            Get-SqlTypeNameKind -SqlType "geography" | Should -BeNullOrEmpty
        }

        It "overrides the CLR type: a bit column holding a string still resolves to Boolean" {
            Get-QueryResultValueKind -Value "True" -SqlType "bit" | Should -Be "Boolean"
        }

        It "never overrides NULL" {
            Get-QueryResultValueKind -Value $null -SqlType "int" | Should -Be "Null"
        }

        It "matches the type name under tr-TR, where a culture-sensitive fold of 'INT' does not produce 'int'" {
            # The Turkish dotless i. ToLower() here would yield "ınt" and every type in the table
            # would silently fall through to the CLR type.
            $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo("tr-TR")
                Get-SqlTypeNameKind -SqlType "INT" | Should -Be "Integer"
                Get-SqlTypeNameKind -SqlType "NVARCHAR(50)" | Should -Be "String"
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $Original
            }
        }
    }
}
