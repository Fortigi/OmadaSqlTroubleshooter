#Requires -Version 7.0
# The statement on one line, as the Results header and the text output show it.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SingleLineSqlText.ps1")
}

Describe 'ConvertTo-SingleLineSqlText' -Tag 'Unit' {

    It 'puts the example from the request on one line, comment included' {
        $Private:Sql = "--Test query 1`r`nSELECT *`r`nFROM Test`r`nWHERE Id = 1"

        ConvertTo-SingleLineSqlText -Text $Private:Sql | Should -BeExactly "--Test query 1 SELECT * FROM Test WHERE Id = 1"
    }

    It 'trims every line and drops empty ones, whatever the line endings' {
        $Private:Sql = "  SELECT a,`n`t    b`r`n`r`n   FROM t  `rWHERE 1 = 1   "

        ConvertTo-SingleLineSqlText -Text $Private:Sql | Should -BeExactly "SELECT a, b FROM t WHERE 1 = 1"
    }

    It 'leaves the spacing inside a line alone' {
        ConvertTo-SingleLineSqlText -Text "SELECT 'a  b'" | Should -BeExactly "SELECT 'a  b'"
    }

    It 'returns an empty string for <Case>' -ForEach @(
        @{ Case = "null"; Value = $null },
        @{ Case = "empty"; Value = "" },
        @{ Case = "whitespace and line breaks"; Value = " `r`n `t " }
    ) {
        ConvertTo-SingleLineSqlText -Text $Value | Should -BeExactly ""
    }

    It 'caps a long line at MaxLength, ellipsis included' {
        $Private:Result = ConvertTo-SingleLineSqlText -Text ("x" * 50) -MaxLength 10

        $Private:Result.Length | Should -Be 10
        $Private:Result | Should -BeExactly (("x" * 9) + [char]0x2026)
    }

    It 'caps at 1024 characters by default' {
        (ConvertTo-SingleLineSqlText -Text ("x" * 5000)).Length | Should -Be 1024
    }

    It 'does not cap a line of exactly MaxLength' {
        ConvertTo-SingleLineSqlText -Text ("x" * 10) -MaxLength 10 | Should -BeExactly ("x" * 10)
    }

    It 'returns the whole line with -NoCap' {
        (ConvertTo-SingleLineSqlText -Text ("x" * 5000) -NoCap).Length | Should -Be 5000
    }
}
