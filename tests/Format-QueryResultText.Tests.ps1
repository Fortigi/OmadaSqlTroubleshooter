#Requires -Version 7.0
# Results to Text: every statement's result rendered into one text, SSMS style, with a header block
# per statement (Statement, Rows, Query name, Query).

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SingleLineSqlText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Format-QueryResultText.ps1")

    function script:New-StatementResult {
        param(
            [int]$Ordinal = 1,
            [string]$DisplayText = "SELECT 1",
            [object[]]$Rows = @()
        )

        return [pscustomobject]@{
            Ordinal     = $Ordinal
            DisplayText = $DisplayText
            Rows        = $Rows
            RowCount    = @($Rows).Count
        }
    }

    function script:Get-TextLine {
        param([string]$Text)
        return @($Text -split "`r`n")
    }
}

Describe 'Format-QueryResultText' -Tag 'Unit' {

    Context 'The header block of a statement' {

        It 'writes Statement, Rows, Query name and Query, then a blank line, then the table' {
            $Private:Statement = New-StatementResult -Ordinal 1 -DisplayText "--Test query 1`r`nSELECT *`r`nFROM Test`r`nWHERE Id = 1" -Rows @(
                [pscustomobject]@{ Id = 1; Name = "foo" }
            )

            $Private:Line = Get-TextLine (Format-QueryResultText -StatementResult @($Private:Statement) -QueryName "My saved query")

            $Private:Line[0] | Should -BeExactly "Statement: 1"
            $Private:Line[1] | Should -BeExactly "Rows: 1 row(s)"
            $Private:Line[2] | Should -BeExactly "Query name: My saved query"
            $Private:Line[3] | Should -BeExactly "Query: --Test query 1 SELECT * FROM Test WHERE Id = 1"
            $Private:Line[4] | Should -BeExactly ""
            $Private:Line[5] | Should -BeExactly "Id Name"
        }

        It 'shows the whole query, without the cap the grid header uses' {
            $Private:LongQuery = "SELECT " + ("x" * 3000)
            $Private:Text = Format-QueryResultText -StatementResult @(New-StatementResult -DisplayText $Private:LongQuery) -QueryName "q"

            (Get-TextLine $Private:Text)[3] | Should -BeExactly ("Query: " + $Private:LongQuery)
        }
    }

    Context 'The table' {

        BeforeAll {
            $script:Rendered = Format-QueryResultText -QueryName "q" -StatementResult @(
                (New-StatementResult -Rows @(
                    [pscustomobject]@{ Id = 1; Name = "alpha"; Active = $true; Note = $null },
                    [pscustomobject]@{ Id = 1234; Name = "b"; Active = $false; Note = "x" }
                ))
            )
            $script:RenderedLine = Get-TextLine $script:Rendered
        }

        It 'sizes each column to its longest value or name and underlines it with dashes' {
            $script:RenderedLine[5] | Should -BeExactly "Id   Name  Active Note"
            $script:RenderedLine[6] | Should -BeExactly "---- ----- ------ ----"
        }

        It 'right-aligns numbers and writes NULL, 1 and 0' {
            $script:RenderedLine[7] | Should -BeExactly "   1 alpha 1      NULL"
            $script:RenderedLine[8] | Should -BeExactly "1234 b     0      x"
        }

        It 'ends with a blank line, the affected count and another blank line' {
            $script:RenderedLine[9] | Should -BeExactly ""
            $script:RenderedLine[10] | Should -BeExactly "(2 row(s) affected)"
            $script:RenderedLine[11] | Should -BeExactly ""
        }

        It 'formats a date the way SSMS does' {
            $Private:Text = Format-QueryResultText -QueryName "q" -StatementResult @(
                New-StatementResult -Rows @([pscustomobject]@{ At = [datetime]::new(2026, 11, 17, 9, 5, 3, 42) })
            )

            (Get-TextLine $Private:Text)[7] | Should -BeExactly "2026-11-17 09:05:03.042"
        }

        It 'replaces a line break inside a value with a space' {
            $Private:Text = Format-QueryResultText -QueryName "q" -StatementResult @(
                New-StatementResult -Rows @([pscustomobject]@{ Value = "one`r`ntwo`nthree" })
            )

            (Get-TextLine $Private:Text)[7] | Should -BeExactly "one two three"
        }

        It 'cuts a value off at MaxColumnWidth' {
            $Private:Text = Format-QueryResultText -QueryName "q" -MaxColumnWidth 5 -StatementResult @(
                New-StatementResult -Rows @([pscustomobject]@{ V = "abcdefghij" })
            )

            (Get-TextLine $Private:Text)[7] | Should -BeExactly "abcde"
        }

        It 'left-aligns a column that mixes numbers and text' {
            $Private:Text = Format-QueryResultText -QueryName "q" -StatementResult @(
                New-StatementResult -Rows @(
                    [pscustomobject]@{ V = 7; W = "z" },
                    [pscustomobject]@{ V = "seven"; W = "z" }
                )
            )

            (Get-TextLine $Private:Text)[7] | Should -BeExactly "7     z"
        }
    }

    Context 'Several statements' {

        It 'puts every statement into one text, in order, a 0-row statement included' {
            $Private:Text = Format-QueryResultText -QueryName "q" -StatementResult @(
                (New-StatementResult -Ordinal 1 -Rows @([pscustomobject]@{ A = 1 })),
                (New-StatementResult -Ordinal 2 -DisplayText "SELECT 2 WHERE 1 = 0"),
                (New-StatementResult -Ordinal 4 -Rows @([pscustomobject]@{ B = "x" }))
            )

            $Private:Line = Get-TextLine $Private:Text
            @($Private:Line | Where-Object { $_ -like "Statement: *" }) | Should -Be @("Statement: 1", "Statement: 2", "Statement: 4")
        }

        It 'gives a 0-row statement its header block and the affected count, without a table' {
            $Private:Line = Get-TextLine (Format-QueryResultText -QueryName "q" -StatementResult @(New-StatementResult -Ordinal 2 -DisplayText "SELECT 2"))

            $Private:Line[0..6] | Should -Be @("Statement: 2", "Rows: 0 row(s)", "Query name: q", "Query: SELECT 2", "", "(0 row(s) affected)", "")
        }

        It 'returns an empty string when there is nothing to show' {
            Format-QueryResultText -StatementResult @() -QueryName "q" | Should -BeExactly ""
            Format-QueryResultText -StatementResult $null | Should -BeExactly ""
        }
    }
}
