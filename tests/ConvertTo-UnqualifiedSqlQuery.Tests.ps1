BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SqlParserType.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SqlScriptFragment.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SqlFragmentDescendant.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-UnqualifiedSqlQuery.ps1")

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

    $Script:ScriptDomAvailable = $null -ne (Get-SqlParserType)
}

Describe 'ConvertTo-UnqualifiedSqlQuery' {
    BeforeEach {
        if (-not $Script:ScriptDomAvailable) {
            Set-ItResult -Skipped -Because "ScriptDom is not loaded in this session"
        }
    }

    Context 'stripping the database prefix (issue #152 criterion 6)' {
        It 'removes [Db]. from [Db].[Schema].[Table]' {
            ConvertTo-UnqualifiedSqlQuery -SqlText "SELECT * FROM [DatabaseA].[Schema].[Table]" |
                Should -Be "SELECT * FROM [Schema].[Table]"
        }

        It 'removes Db. from Db.Schema.Table' {
            ConvertTo-UnqualifiedSqlQuery -SqlText "SELECT * FROM DatabaseA.dbo.Person p WHERE p.Id = 1" |
                Should -Be "SELECT * FROM dbo.Person p WHERE p.Id = 1"
        }

        It 'removes the whole [Db].. of the two-dot form, leaving no leading dot' {
            ConvertTo-UnqualifiedSqlQuery -SqlText "SELECT * FROM [DatabaseA]..[Person]" |
                Should -Be "SELECT * FROM [Person]"
        }

        It 'removes every prefix when one statement names the same database twice' {
            ConvertTo-UnqualifiedSqlQuery -SqlText "SELECT * FROM [A].[dbo].[X] x JOIN [A].[dbo].[Y] y ON 1 = 1" |
                Should -Be "SELECT * FROM [dbo].[X] x JOIN [dbo].[Y] y ON 1 = 1"
        }
    }

    Context 'stripping USE' {
        It 'removes a bare USE, leaving nothing to execute' {
            ConvertTo-UnqualifiedSqlQuery -SqlText "USE [DatabaseA]" | Should -BeNullOrEmpty
        }

        It 'removes USE and its semicolon, keeping the statements after it' {
            $Result = ConvertTo-UnqualifiedSqlQuery -SqlText "USE [DatabaseA];`r`nSELECT * FROM [dbo].[Person]"
            $Result.Trim() | Should -Be "SELECT * FROM [dbo].[Person]"
            $Result | Should -Not -Match "USE"
        }
    }

    Context 'text that must be left alone (issue #152 criterion 15)' {
        It 'leaves a database-qualified name inside a string literal untouched' {
            $Sql = "SELECT '[DatabaseA].[dbo].[Person]' AS Text"
            ConvertTo-UnqualifiedSqlQuery -SqlText $Sql | Should -Be $Sql
        }

        It 'leaves a database-qualified name inside a line comment untouched' {
            $Sql = "SELECT 1 -- FROM [DatabaseA].[dbo].[Person]"
            ConvertTo-UnqualifiedSqlQuery -SqlText $Sql | Should -Be $Sql
        }

        It 'leaves a database-qualified name inside a block comment untouched' {
            $Sql = "SELECT 1 /* FROM [DatabaseA].[dbo].[Person] */"
            ConvertTo-UnqualifiedSqlQuery -SqlText $Sql | Should -Be $Sql
        }

        It 'returns a query with no database prefix unchanged' {
            $Sql = "SELECT * FROM [dbo].[Person]"
            ConvertTo-UnqualifiedSqlQuery -SqlText $Sql | Should -Be $Sql
        }
    }

    Context 'input that cannot be rewritten' {
        It 'returns empty input unchanged' {
            ConvertTo-UnqualifiedSqlQuery -SqlText "" | Should -Be ""
        }

        It 'returns null input unchanged' {
            ConvertTo-UnqualifiedSqlQuery -SqlText $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'ConvertTo-UnqualifiedSqlQuery without ScriptDom' {
    It 'returns the text unchanged rather than throwing when the parser is missing' {
        function Get-SqlScriptFragment {
            param($SqlText, $ParserVersion)
            return [PSCustomObject]@{ Status = "Unavailable"; Fragment = $null; ParseError = @(); ParserVersion = $null }
        }

        $Sql = "SELECT * FROM [A].[dbo].[X]"
        ConvertTo-UnqualifiedSqlQuery -SqlText $Sql | Should -Be $Sql
    }
}
