#Requires -Version 7.0
# Tests for the type resolution behind issue #103's "Copy as SQL/PowerShell array".
#
# The point of these assertions is the NEGATIVE ones: a string that looks like a number must stay a
# string. The pre-#103 behaviour resolved types by matching the rendered text against "^-?\d+$",
# which is exactly what turns the code "007" into 7 and compares an nvarchar column as an int.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    # Resolve-StrictBoolean first: Resolve-ColumnBooleanValue defers the decisions it shares with it
    # rather than making a second copy of them.
    . (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Resolve-StrictBoolean.ps1")
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

        It "never produces Date from refinement, only from a declared date column" {
            # The asymmetry is deliberate: a bare "2019-01-01" in a string column could be a product
            # code, so it is left a string. A column DECLARED date carries no such doubt.
            Get-QueryResultValueKind -Value "2019-01-01" | Should -Be "String"
            Get-QueryResultValueKind -Value "2019-01-01" -SqlType "date" | Should -Be "Date"
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
            @{ SqlType = "date"; Expected = "Date" }
            @{ SqlType = "datetime"; Expected = "DateTime" }
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

Describe "Get-CanonicalNumericStringKind" {
    # Issue #120. Everything here is about what must NOT be promoted: the whole value of the rule is
    # that a text that is a number in more than one way stays text.

    Context "Canonical numbers" {
        It "accepts <Name> as <Expected>" -ForEach @(
            @{ Name = "a plain integer"; Value = "900"; Expected = "Integer" }
            @{ Name = "zero"; Value = "0"; Expected = "Integer" }
            @{ Name = "a negative integer"; Value = "-42"; Expected = "Integer" }
            @{ Name = "a decimal"; Value = "12.50"; Expected = "Decimal" }
            @{ Name = "a decimal below one"; Value = "0.75"; Expected = "Decimal" }
            @{ Name = "a negative decimal"; Value = "-3.20"; Expected = "Decimal" }
        ) {
            Get-CanonicalNumericStringKind -Value $Value | Should -Be $Expected
        }
    }

    Context "Everything a promotion would change" {
        It "refuses <Name>" -ForEach @(
            @{ Name = "a leading zero"; Value = "007" }
            @{ Name = "several leading zeros"; Value = "00" }
            @{ Name = "a leading plus"; Value = "+7" }
            @{ Name = "surrounding whitespace"; Value = " 7 " }
            @{ Name = "a thousands separator"; Value = "1,000" }
            @{ Name = "a decimal comma"; Value = "12,50" }
            @{ Name = "an exponent"; Value = "1e3" }
            @{ Name = "hexadecimal"; Value = "0x1F" }
            @{ Name = "a trailing point"; Value = "12." }
            @{ Name = "a bare point"; Value = "." }
            @{ Name = "a currency symbol"; Value = "$7" }
            @{ Name = "a percentage"; Value = "50%" }
            @{ Name = "text"; Value = "IDG-900" }
            @{ Name = "the empty string"; Value = "" }
            @{ Name = "a value too wide for Int64"; Value = "99999999999999999999" }
        ) {
            Get-CanonicalNumericStringKind -Value $Value | Should -BeNullOrEmpty
        }
    }

    Context "Culture independence" {
        It "gives the same answer under nl-NL, en-US and tr-TR" {
            $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $Result = [System.Collections.Generic.List[string]]::new()

            try {
                foreach ($CultureName in @("nl-NL", "en-US", "tr-TR")) {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($CultureName)
                    $Answer = @("12.50", "12,50", "007") | ForEach-Object { [string](Get-CanonicalNumericStringKind -Value $_) }
                    $Result.Add($Answer -join "|")
                }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $Original
            }

            @($Result | Select-Object -Unique).Count | Should -Be 1
            $Result[0] | Should -BeExactly "Decimal||"
        }
    }
}

Describe "Resolve-ColumnBooleanValue" {

    It "resolves <Name> to <Expected>" -ForEach @(
        @{ Name = "a real boolean"; Value = $true; Expected = $true }
        @{ Name = "the text True"; Value = "True"; Expected = $true }
        @{ Name = "the text false"; Value = "false"; Expected = $false }
        @{ Name = "the text 1 - a bit rendered as a number"; Value = "1"; Expected = $true }
        @{ Name = "the text 0"; Value = "0"; Expected = $false }
        @{ Name = "the integer 0"; Value = 0; Expected = $false }
    ) {
        Resolve-ColumnBooleanValue -Value $Value | Should -Be $Expected
    }

    It "refuses <Name>, which is not a bit this can vouch for" -ForEach @(
        @{ Name = "arbitrary text"; Value = "maybe" }
        @{ Name = "the empty string"; Value = "" }
        @{ Name = "a non-canonical number"; Value = "01" }
        @{ Name = "a guid"; Value = [guid]::Empty }
    ) {
        Resolve-ColumnBooleanValue -Value $Value | Should -BeNullOrEmpty
    }
}

Describe "Test-QueryResultValueFitsKind" {
    # The corroboration step: a declared SQL type is only honoured where the values bear it out.

    It "accepts <Value> as <Kind>" -ForEach @(
        @{ Value = "900"; Kind = "Integer" }
        @{ Value = 900; Kind = "Integer" }
        @{ Value = "12.50"; Kind = "Decimal" }
        @{ Value = "1e3"; Kind = "Float" }
        @{ Value = "False"; Kind = "Boolean" }
        @{ Value = "0f6a1b3c-1111-4a2b-9c01-a00000000900"; Kind = "Guid" }
        @{ Value = "2019-11-20T13:55:09"; Kind = "DateTime" }
        @{ Value = "13:55:09"; Kind = "Time" }
        @{ Value = "anything at all"; Kind = "String" }
        @{ Value = $null; Kind = "Integer" }
    ) {
        Test-QueryResultValueFitsKind -Value $Value -Kind $Kind | Should -BeTrue
    }

    It "refuses <Value> as <Kind>" -ForEach @(
        @{ Value = "007"; Kind = "Integer" }
        @{ Value = "IDG-900"; Kind = "Integer" }
        @{ Value = $true; Kind = "Integer" }
        @{ Value = "12,50"; Kind = "Decimal" }
        @{ Value = "not a guid"; Kind = "Guid" }
        @{ Value = "20-11-2019"; Kind = "DateTime" }
        @{ Value = "maybe"; Kind = "Boolean" }
        @{ Value = "0x0A1B"; Kind = "Binary" }
    ) {
        Test-QueryResultValueFitsKind -Value $Value -Kind $Kind | Should -BeFalse
    }

    It "refuses a locale-rendered date under every culture, rather than reading it under one" {
        $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            foreach ($CultureName in @("nl-NL", "en-US", "tr-TR")) {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($CultureName)
                Test-QueryResultValueFitsKind -Value "20-11-2019 13:55:09" -Kind "DateTime" | Should -BeFalse
            }
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $Original
        }
    }
}

Describe "Test-QueryResultRowIsUntyped" {
    # The switch that decides whether value promotion may run at all.

    It "calls a response with a JSON number typed" {
        $Row = @('{ "Id": 900, "Number": "IDG-900" }' | ConvertFrom-Json)
        Test-QueryResultRowIsUntyped -Row $Row | Should -BeFalse
    }

    It "calls a response with a JSON boolean typed" {
        $Row = @('{ "Deleted": false, "Number": "IDG-900" }' | ConvertFrom-Json)
        Test-QueryResultRowIsUntyped -Row $Row | Should -BeFalse
    }

    It "calls a response whose cells are all strings untyped" {
        $Row = @('{ "Id": "900", "Number": "IDG-900", "ParentID": null }' | ConvertFrom-Json)
        Test-QueryResultRowIsUntyped -Row $Row | Should -BeTrue
    }

    It "does not count a rehydrated timestamp as a type" {
        # ConvertFrom-Json turns an ISO 8601 string into a [datetime] whether or not the payload was
        # typed, so a date says nothing about the rest of the response.
        $Row = @('{ "CreateTime": "2019-11-20T13:55:09", "Id": "900" }' | ConvertFrom-Json)
        Test-QueryResultRowIsUntyped -Row $Row | Should -BeTrue
    }

    It "finds the evidence in a later row too" {
        $Row = @('{ "Id": "900" }', '{ "Id": 901 }') | ForEach-Object { $_ | ConvertFrom-Json }
        Test-QueryResultRowIsUntyped -Row $Row | Should -BeFalse
    }

    It "stops after MaximumRow rows rather than reading a whole result set" {
        $Row = @(1..10 | ForEach-Object { '{ "Id": "900" }' | ConvertFrom-Json })
        $Row += ('{ "Id": 901 }' | ConvertFrom-Json)

        Test-QueryResultRowIsUntyped -Row $Row -MaximumRow 5 | Should -BeTrue -Because "the typed row is beyond the inspection limit"
        Test-QueryResultRowIsUntyped -Row $Row | Should -BeFalse
    }

    It "treats no rows as untyped" {
        Test-QueryResultRowIsUntyped -Row @() | Should -BeTrue
    }
}
