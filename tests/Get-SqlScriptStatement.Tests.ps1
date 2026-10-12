#Requires -Version 7.0
# Tests for the statement splitter of issue #151 - the piece that turns the text about to be executed
# into one query per statement, so a script with several statements produces one result grid each.
#
# The split runs against the real, pinned ScriptDom assembly rather than a stand-in, for the same
# reason the three validation passes of issue #61 do: the whole point of the dependency is that it
# produces SQL Server's own syntax tree. A fake parser would happily agree that a semicolon inside a
# string literal ends a statement - which is precisely the bug that rules out splitting on ";" with a
# regular expression, and therefore the thing most worth proving here.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptFragment.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptStatement.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    $script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath

    # Once loaded, an assembly cannot be unloaded from a PowerShell session, so "ScriptDom is missing"
    # is exercised by making the resolver report nothing rather than by unloading anything.
    # Get-SqlScriptFragment asks Get-SqlParserType and has no other route to a parser, so this is the
    # whole of the missing-assembly path.
    function Use-MissingScriptDom {
        param([scriptblock]$Body)

        $Original = ${function:Get-SqlParserType}
        try {
            Set-Item -Path "function:Get-SqlParserType" -Value { param($ParserVersion) return $null }
            & $Body
        }
        finally {
            Set-Item -Path "function:Get-SqlParserType" -Value $Original
        }
    }
}

Describe 'Get-SqlScriptStatement' -Tag 'Unit' {

    BeforeEach {
        # -Skip: is evaluated at discovery, when the BeforeAll variable is still null, so the
        # unavailable-parser case is reported at run time instead. An offline agent is not a failure.
        if ([string]::IsNullOrWhiteSpace($script:ScriptDomPath)) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom assembly could not be resolved on this agent"
        }
    }

    Context 'When the script holds several statements' {

        It 'returns one statement per statement, in editor order' {
            # The acceptance criterion this file exists for: two SELECTs, executed with nothing
            # selected, must become two queries.
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT 1;`r`nSELECT 2;")

            $Private:Statement.Count | Should -Be 2
            $Private:Statement[0].Text | Should -Match 'SELECT\s+1'
            $Private:Statement[1].Text | Should -Match 'SELECT\s+2'
        }

        It 'numbers the statements from one, in editor order' {
            # The ordinal is what the Results pane header and the Messages summary both label a result
            # with, so "statement 2" has to mean the second one in the editor and not the second one
            # that happened to come back.
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT 1;`r`nSELECT 2;`r`nSELECT 3;")

            @($Private:Statement.Ordinal) | Should -Be @(1, 2, 3)
        }

        It 'keeps each statement as its own text rather than the whole script' {
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT 1;`r`nSELECT 2;")

            $Private:Statement[0].Text | Should -Not -Match 'SELECT\s+2'
            $Private:Statement[1].Text | Should -Not -Match 'SELECT\s+1'
        }

        It 'splits statements that are not separated by a semicolon at all' {
            # T-SQL does not require the separator, and a user pasting two SELECTs on two lines without
            # one is not writing an error. ScriptDom ends a statement where the grammar does, which a
            # ";"-based split could never do.
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT 1`r`nSELECT 2")

            $Private:Statement.Count | Should -Be 2
        }

        It 'splits across GO-separated batches and keeps editor order' {
            # GO is a batch separator, not a statement terminator: the parse tree holds several
            # batches, so the walk has to descend through Batches[] rather than stopping at the first.
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT 1;`r`nGO`r`nSELECT 2;")

            $Private:Statement.Count | Should -Be 2
            $Private:Statement[0].Text | Should -Match 'SELECT\s+1'
            $Private:Statement[1].Text | Should -Match 'SELECT\s+2'
        }
    }

    Context 'When a semicolon does not end a statement' {

        It 'does not split on a semicolon inside a string literal' {
            # The reason ScriptDom is used instead of a regular expression. A ";"-split turns this one
            # query into two fragments, neither of which is valid SQL, and the user gets two failures
            # for a query that was correct.
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT 'a;b' AS Value")

            $Private:Statement.Count | Should -Be 1
            $Private:Statement[0].Text | Should -Match "a;b"
        }

        It 'does not split on a semicolon inside a line comment' {
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT 1 -- what about ; this`r`n")

            $Private:Statement.Count | Should -Be 1
        }

        It 'does not split on a semicolon inside a block comment' {
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT /* a ; b */ 1")

            $Private:Statement.Count | Should -Be 1
        }
    }

    Context 'When the statement carries formatting of its own' {

        It 'preserves the formatting inside a statement rather than normalising it' {
            # The text is what gets written to the temporary query object and executed, so it has to be
            # the user's own SQL. Cutting the source by offset preserves it; rebuilding the statement
            # from the tree would not.
            $Private:Sql = "SELECT`r`n    Name,`r`n    Id`r`nFROM dbo.Thing"
            $Private:Statement = @(Get-SqlScriptStatement -SqlText $Private:Sql)

            $Private:Statement.Count | Should -Be 1
            $Private:Statement[0].Text | Should -Match "Name,"
            $Private:Statement[0].Text | Should -Match "`r`n"
        }

        It 'preserves a comment that sits inside the statement' {
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT /* keep me */ 1")

            $Private:Statement[0].Text | Should -Match 'keep me'
        }
    }

    Context 'When the script cannot be split safely' {

        It 'falls back to a single statement when the script does not parse' {
            # "A script the parser did not understand must not be silently mis-split" - issue #151.
            # One statement carrying the original text is exactly today's behaviour, so a script that
            # defeats the parser still runs the way it always has.
            $Private:Sql = "SELECT FROM WHERE ((("
            $Private:Statement = @(Get-SqlScriptStatement -SqlText $Private:Sql)

            $Private:Statement.Count | Should -Be 1
            $Private:Statement[0].Text | Should -Be $Private:Sql
        }

        It 'falls back to a single statement when ScriptDom is not loaded' {
            Use-MissingScriptDom {
                $Private:Sql = "SELECT 1;`r`nSELECT 2;"
                $Private:Statement = @(Get-SqlScriptStatement -SqlText $Private:Sql)

                # Two statements in the text, but nothing that could prove where one ends: it runs as
                # one query, as it does today.
                $Private:Statement.Count | Should -Be 1
                $Private:Statement[0].Text | Should -Be $Private:Sql
            }
        }

        It 'falls back to a single statement for a script that parses to nothing' {
            # A script of only comments has no statements in its tree. Returning nothing here would
            # execute nothing at all, where today the text is sent and the tenant answers - so the
            # fallback keeps the user's run happening rather than silently swallowing it.
            $Private:Sql = "-- nothing but a comment"
            $Private:Statement = @(Get-SqlScriptStatement -SqlText $Private:Sql)

            $Private:Statement.Count | Should -Be 1
            $Private:Statement[0].Text | Should -Be $Private:Sql
        }

        It 'falls back to a single statement for whitespace-only text' {
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "   ")

            $Private:Statement.Count | Should -Be 1
            $Private:Statement[0].Text | Should -Be "   "
        }

        It 'falls back to a single empty statement for empty text' {
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "")

            $Private:Statement.Count | Should -Be 1
            $Private:Statement[0].Text | Should -Be ""
        }

        It 'falls back to a single statement for null text' {
            # Null and empty are the same answer as today's: hand the pipeline what it was given and
            # let the existing precondition checks deal with it.
            $Private:Statement = @(Get-SqlScriptStatement -SqlText $null)

            $Private:Statement.Count | Should -Be 1
            [string]::IsNullOrEmpty($Private:Statement[0].Text) | Should -BeTrue
        }
    }

    Context 'When one statement is all there is' {

        It 'returns exactly one statement, which is what keeps a single execute identical to today' {
            # Acceptance criterion: "Selecting one of those statements and executing produces exactly
            # one result grid - identical to today." One statement in, one query out, one grid.
            $Private:Statement = @(Get-SqlScriptStatement -SqlText "SELECT TOP 10 * FROM dbo.Thing")

            $Private:Statement.Count | Should -Be 1
        }
    }

    Context 'The shape it reports' {

        It 'reports an offset and a length that cut the statement out of the original text' {
            # The offsets are the cut itself, so they are asserted rather than taken on trust: a
            # length that is one character short silently truncates the user's SQL, which the tenant
            # would then reject for a reason nothing in the application could explain.
            $Private:Sql = "SELECT 1;`r`nSELECT 2;"
            $Private:Statement = @(Get-SqlScriptStatement -SqlText $Private:Sql)

            foreach ($Private:Item in $Private:Statement) {
                $Private:Item.StartOffset | Should -BeGreaterOrEqual 0
                $Private:Item.Length | Should -BeGreaterThan 0
                ($Private:Item.StartOffset + $Private:Item.Length) | Should -BeLessOrEqual $Private:Sql.Length
                $Private:Sql.Substring($Private:Item.StartOffset, $Private:Item.Length) | Should -Be $Private:Item.Text
            }
        }
    }
}
