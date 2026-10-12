BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SqlParserType.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SqlScriptFragment.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SqlFragmentDescendant.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SqlDatabaseReference.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    # ScriptDom is downloaded at runtime by Install-ScriptDom, so it is not guaranteed to be present
    # on a build agent. Every test that needs a real parse is skipped rather than failed when it is
    # missing - "could not look" is not the same answer as "wrong", which is the distinction
    # Get-SqlScriptFragment itself is built around.
    $Script:ScriptDomAvailable = $null -ne (Get-SqlParserType)
}

Describe 'Get-SqlDatabaseReference' {
    BeforeEach {
        if (-not $Script:ScriptDomAvailable) {
            Set-ItResult -Skipped -Because "ScriptDom is not loaded in this session"
        }
    }

    Context 'the accepted name forms (issue #152 criterion 3)' {
        It 'finds the database in [Db].[Schema].[Table]' {
            $Result = Get-SqlDatabaseReference -SqlText "SELECT * FROM [DatabaseA].[Schema].[Table]"
            $Result.Status | Should -Be "Ok"
            $Result.Database | Should -Be @("DatabaseA")
            $Result.Rejection | Should -BeNullOrEmpty
        }

        It 'finds the database in Db.Schema.Table' {
            (Get-SqlDatabaseReference -SqlText "SELECT * FROM DatabaseA.dbo.Person").Database | Should -Be @("DatabaseA")
        }

        It 'finds the database in the two-dot [Db]..[Table] form' {
            (Get-SqlDatabaseReference -SqlText "SELECT * FROM [DatabaseA]..[Person]").Database | Should -Be @("DatabaseA")
        }

        It 'accepts a mix of bracketed and bare identifiers' {
            (Get-SqlDatabaseReference -SqlText "SELECT * FROM DatabaseA.[dbo].Person").Database | Should -Be @("DatabaseA")
        }

        It 'treats differently cased spellings of one database as the same database' {
            $Result = Get-SqlDatabaseReference -SqlText "SELECT * FROM [DatabaseA].[dbo].[A] a JOIN [databasea].[dbo].[B] b ON 1 = 1"
            $Result.Database.Count | Should -Be 1
            $Result.Rejection | Should -BeNullOrEmpty
        }
    }

    Context 'statements that address no database' {
        It 'reports nothing for an unqualified query' {
            $Result = Get-SqlDatabaseReference -SqlText "SELECT * FROM [dbo].[Person]"
            $Result.Status | Should -Be "Ok"
            $Result.Database.Count | Should -Be 0
            $Result.UseDatabase | Should -BeNullOrEmpty
        }

        It 'reports nothing for empty input' {
            (Get-SqlDatabaseReference -SqlText "").Database.Count | Should -Be 0
        }

        It 'reports nothing for null input' {
            (Get-SqlDatabaseReference -SqlText $null).Database.Count | Should -Be 0
        }
    }

    Context 'USE (issue #152 section 2)' {
        It 'reports the database named by USE' {
            $Result = Get-SqlDatabaseReference -SqlText "USE [DatabaseA]"
            $Result.UseDatabase | Should -Be "DatabaseA"
            $Result.Database | Should -Be @("DatabaseA")
        }

        It 'reports the last USE when several appear' {
            (Get-SqlDatabaseReference -SqlText "USE [A]`r`nUSE [A]").UseDatabase | Should -Be "A"
        }

        It 'accepts USE followed by statements against the same database' {
            $Result = Get-SqlDatabaseReference -SqlText "USE [DatabaseA]`r`nSELECT * FROM [dbo].[Person]"
            $Result.UseDatabase | Should -Be "DatabaseA"
            $Result.Rejection | Should -BeNullOrEmpty
        }
    }

    Context 'rejections decided before anything is posted' {
        It 'rejects one statement naming two databases (criterion 8)' {
            $Result = Get-SqlDatabaseReference -SqlText "SELECT * FROM [A].[dbo].[X] x JOIN [B].[dbo].[Y] y ON 1 = 1"
            $Result.Rejection | Should -Be "CrossDatabase"
            $Result.Message | Should -Match "A, B"
        }

        It 'rejects a four-part linked server name (criterion 10)' {
            $Result = Get-SqlDatabaseReference -SqlText "SELECT * FROM [Srv].[Db].[dbo].[Person]"
            $Result.Rejection | Should -Be "FourPartName"
            $Result.Message | Should -Match "linked server"
        }
    }

    Context 'the contract is per text, and the caller passes one statement' {
        # The rule is "the text I am given names at most one database". Since issue #151 the caller
        # passes ONE statement, so that rule IS criterion 8 - a statement joining two databases
        # cannot run against a single connection. A SCRIPT spanning databases is legal and is
        # Resolve-SqlStatementTarget's job, which is why there is no script-level case here.
        It 'rejects multi-statement text, because it cannot be routed as one query' {
            # This is what the Get-SqlScriptStatement fallback produces when it cannot split safely
            # - no parser, or parse errors - and refusing is the safe answer: without a split there
            # is no way to send each statement to its own connection.
            (Get-SqlDatabaseReference -SqlText "SELECT * FROM [A].[dbo].[X]`r`nSELECT * FROM [B].[dbo].[Y]").Rejection |
                Should -Be "CrossDatabase"
        }

        It 'accepts multi-statement text that names only one database' {
            $Result = Get-SqlDatabaseReference -SqlText "SELECT * FROM [A].[dbo].[X]`r`nSELECT * FROM [A].[dbo].[Y]"
            $Result.Rejection | Should -BeNullOrEmpty
            $Result.Database | Should -Be @("A")
        }
    }

    Context 'text that only looks like a reference (issue #152 criterion 15)' {
        It 'ignores a database-qualified name inside a string literal' {
            (Get-SqlDatabaseReference -SqlText "SELECT '[DatabaseA].[dbo].[Person]' AS Text").Database.Count | Should -Be 0
        }

        It 'ignores a database-qualified name inside a line comment' {
            (Get-SqlDatabaseReference -SqlText "SELECT 1 -- FROM [DatabaseA].[dbo].[Person]").Database.Count | Should -Be 0
        }

        It 'ignores a database-qualified name inside a block comment' {
            (Get-SqlDatabaseReference -SqlText "SELECT 1 /* FROM [DatabaseA].[dbo].[Person] */").Database.Count | Should -Be 0
        }

        It 'ignores a USE inside a comment' {
            (Get-SqlDatabaseReference -SqlText "-- USE [DatabaseA]`r`nSELECT 1").UseDatabase | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-SqlDatabaseReference without ScriptDom' {
    It 'reports Unavailable rather than throwing when the parser is missing' {
        # Get-SqlScriptFragment already contracts to return Unavailable; this asserts that
        # Get-SqlDatabaseReference passes that through instead of treating it as "no database".
        function Get-SqlScriptFragment {
            param($SqlText, $ParserVersion)
            return [PSCustomObject]@{ Status = "Unavailable"; Fragment = $null; ParseError = @(); ParserVersion = $null }
        }

        $Result = Get-SqlDatabaseReference -SqlText "SELECT * FROM [A].[dbo].[X]"
        $Result.Status | Should -Be "Unavailable"
        $Result.Database.Count | Should -Be 0
    }
}
