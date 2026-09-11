BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Format-ClipboardText.ps1")

    # Building a jagged string[][] inline is a trap in PowerShell: @(@("a","b")) flattens to two
    # strings, and @(x, y) does not unwrap the way @(x) does. Piping the rows in sidesteps both -
    # the pipeline unrolls exactly one level, so each row arrives whole.
    #   one row  : , @("only")          | New-RowSet
    #   many rows: @("1","a"), @("2","b") | New-RowSet
    function New-RowSet {
        param(
            [Parameter(ValueFromPipeline = $true)]
            [object]$Row
        )
        begin { $Collected = [System.Collections.Generic.List[string[]]]::new() }
        process { $Collected.Add([string[]]$Row) }
        end { , $Collected.ToArray() }
    }
}

Describe 'Format-ClipboardText' {

    Context 'Default (tab-separated)' {
        It 'should separate cells with a tab and rows with CRLF' {
            $Result = Format-ClipboardText -Row (@("1", "Alice"), @("2", "Bob") | New-RowSet)
            $Result | Should -Be "1`tAlice`r`n2`tBob"
        }

        It 'should prefix the header row when one is given' {
            $Result = Format-ClipboardText -Row (, @("1", "Alice") | New-RowSet) -Header @("Id", "Name")
            $Result | Should -Be "Id`tName`r`n1`tAlice"
        }

        It 'should omit the header row when none is given' {
            $Result = Format-ClipboardText -Row (, @("1", "Alice") | New-RowSet)
            $Result | Should -Be "1`tAlice"
        }

        It 'should pass a single cell through unchanged' {
            Format-ClipboardText -Row (, @("only") | New-RowSet) | Should -Be "only"
        }

        It 'should not escape a value that itself contains a tab or a newline' {
            # Default output is what Excel and SSMS paste back as-is; the DataGrid never produces
            # a multi-line cell, so this documents the behaviour rather than demanding quoting.
            $Result = Format-ClipboardText -Row (, @("left`tright", "first`r`nsecond") | New-RowSet)
            $Result | Should -Be "left`tright`tfirst`r`nsecond"
        }

        It 'should keep non-ASCII characters intact' {
            $Result = Format-ClipboardText -Row (, @("Grüße", "日本語", "🙂") | New-RowSet)
            $Result | Should -Be "Grüße`t日本語`t🙂"
        }

        It 'should keep rows in the order they were given' {
            $Result = Format-ClipboardText -Row (@("c"), @("a"), @("b") | New-RowSet)
            $Result | Should -Be "c`r`na`r`nb"
        }
    }

    Context 'Empty and whitespace selections' {
        It 'should return nothing for no rows at all' {
            Format-ClipboardText -Row @() | Should -BeNullOrEmpty
        }

        It 'should return nothing when every selected value is whitespace' {
            Format-ClipboardText -Row (@(" ", ""), @("", " ") | New-RowSet) | Should -BeNullOrEmpty
        }

        It 'should return nothing for a whitespace-only selection even in SqlArray format' {
            Format-ClipboardText -Row (, @("") | New-RowSet) -OutputFormat SqlArray | Should -BeNullOrEmpty
        }

        It 'should still emit a header-only selection' {
            Format-ClipboardText -Row @() -Header @("Id", "Name") | Should -Be "Id`tName"
        }

        It 'should return nothing for a header-only selection in an array format' -ForEach @(
            @{ Format = "SqlArray" }
            @{ Format = "PowerShellArray" }
        ) {
            # An array literal is built from values, and a header is not one. Without the guard
            # the header alone made the text look non-empty and produced an empty literal.
            Format-ClipboardText -Row @() -Header @("Id", "Name") -OutputFormat $Format | Should -BeNullOrEmpty
        }
    }

    Context 'SqlArray' {
        It 'should emit unquoted values when every value is an integer' {
            $Result = Format-ClipboardText -Row (@("1"), @("2"), @("3") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    1,`r`n    2,`r`n    3`r`n)"
        }

        It 'should treat a negative integer as an integer' {
            $Result = Format-ClipboardText -Row (@("-1"), @("42") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    -1,`r`n    42`r`n)"
        }

        It 'should quote every value when any single one is not an integer' {
            $Result = Format-ClipboardText -Row (@("1"), @("two") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    '1',`r`n    'two'`r`n)"
        }

        It 'should double an apostrophe exactly once' {
            $Result = Format-ClipboardText -Row (, @("O'Brien") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    'O''Brien'`r`n)"
            $Result | Should -Not -Match "O'''Brien"
        }

        It 'should double every apostrophe in a value that has several' {
            $Result = Format-ClipboardText -Row (, @("'a'b'") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    '''a''b'''`r`n)"
        }

        It 'should quote values that only look numeric, because pasting them unquoted would change them' -ForEach @(
            @{ Value = "1.5" }
            @{ Value = "1e3" }
            @{ Value = "+1" }
            @{ Value = " 1" }
            @{ Value = "1 " }
            @{ Value = "0x1F" }
            @{ Value = "1,000" }
        ) {
            $Result = Format-ClipboardText -Row (, @($Value) | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be ("(`r`n    '{0}'`r`n)" -f $Value)
        }

        It 'should emit a zero-padded value unquoted, because \d+ matches it' {
            # Documents current behaviour rather than endorsing it: "007" pastes as the integer 7,
            # which is right for a numeric key and wrong for a zero-padded string key. Changing it
            # would be a behaviour change, out of scope for this test-coverage work.
            Format-ClipboardText -Row (, @("007") | New-RowSet) -OutputFormat SqlArray | Should -Be "(`r`n    007`r`n)"
        }

        It 'should flatten every selected cell across rows and columns into one list' {
            $Result = Format-ClipboardText -Row (@("1", "2"), @("3", "4") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    1,`r`n    2,`r`n    3,`r`n    4`r`n)"
        }

        It 'should ignore the header, since a header is not a value' {
            $Result = Format-ClipboardText -Row (, @("1") | New-RowSet) -Header @("Id") -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    1`r`n)"
        }

        It 'should keep non-ASCII characters inside the quoted literal' {
            $Result = Format-ClipboardText -Row (, @("Grüße") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    'Grüße'`r`n)"
        }

        It 'should quote a value containing a tab or a newline rather than dropping it' {
            $Result = Format-ClipboardText -Row (, @("left`tright") | New-RowSet) -OutputFormat SqlArray
            $Result | Should -Be "(`r`n    'left`tright'`r`n)"
        }
    }

    Context 'PowerShellArray' {
        It 'should emit a single-line unquoted array when every value is an integer' {
            $Result = Format-ClipboardText -Row (@("1"), @("2"), @("3") | New-RowSet) -OutputFormat PowerShellArray
            $Result | Should -Be "@(1, 2, 3)"
        }

        It 'should treat a negative integer as an integer' {
            Format-ClipboardText -Row (, @("-7") | New-RowSet) -OutputFormat PowerShellArray | Should -Be "@(-7)"
        }

        It 'should emit a multi-line quoted array when any value is not an integer' {
            $Result = Format-ClipboardText -Row (@("1"), @("two") | New-RowSet) -OutputFormat PowerShellArray
            $Result | Should -Be "@(`r`n    '1',`r`n    'two'`r`n)"
        }

        It 'should double an apostrophe exactly once' {
            $Result = Format-ClipboardText -Row (, @("O'Brien") | New-RowSet) -OutputFormat PowerShellArray
            $Result | Should -Be "@(`r`n    'O''Brien'`r`n)"
        }

        It 'should quote a value that only looks numeric' {
            Format-ClipboardText -Row (, @("1.5") | New-RowSet) -OutputFormat PowerShellArray | Should -Be "@(`r`n    '1.5'`r`n)"
        }

        It 'should ignore the header' {
            Format-ClipboardText -Row (, @("1") | New-RowSet) -Header @("Id") -OutputFormat PowerShellArray | Should -Be "@(1)"
        }

        It 'should keep non-ASCII characters inside the quoted literal' {
            Format-ClipboardText -Row (, @("日本語") | New-RowSet) -OutputFormat PowerShellArray | Should -Be "@(`r`n    '日本語'`r`n)"
        }
    }

    Context 'Parameter contract' {
        It 'should reject an unknown output format' {
            { Format-ClipboardText -Row (, @("1") | New-RowSet) -OutputFormat "Csv" } | Should -Throw
        }

        It 'should default to the tab-separated format' {
            Format-ClipboardText -Row (, @("1", "2") | New-RowSet) | Should -Be "1`t2"
        }
    }
}
