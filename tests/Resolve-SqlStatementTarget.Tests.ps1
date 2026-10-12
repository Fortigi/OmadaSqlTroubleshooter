BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    foreach ($Function in @(
            "Get-SqlParserType", "Get-SqlScriptFragment", "Get-SqlFragmentDescendant",
            "Get-SqlScriptStatement", "Get-SqlDatabaseReference", "ConvertTo-UnqualifiedSqlQuery",
            "Resolve-DataConnectionReference", "Resolve-SqlStatementTarget")) {
        . (Join-Path $ParentPath -ChildPath ("src\lib\functions\Private\{0}.ps1" -f $Function))
    }

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

    # The statements come from the real splitter, not hand-built objects: the gate consumes exactly
    # what Invoke-ExecuteQuery hands it, and a hand-built shape could drift from that.
    function script:Resolve-Text {
        param([string]$SqlText, [string[]]$OptionList)
        return Resolve-SqlStatementTarget -Statement (Get-SqlScriptStatement -SqlText $SqlText) -OptionList $OptionList
    }
}

Describe 'Resolve-SqlStatementTarget' {
    BeforeEach {
        if (-not $Script:ScriptDomAvailable) {
            Set-ItResult -Skipped -Because "ScriptDom is not loaded in this session"
        }
        $Script:OptionList = @("OISES - 1001572", "ODW - 2003044")
    }

    Context 'a script that addresses no database (issue #152 criterion 14)' {
        It 'reports None and hands the statements back untouched' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "None"
            $Result.Statement.Count | Should -Be 1
            $Result.Statement[0].Text | Should -Be "SELECT * FROM [dbo].[Person]"
            $Result.UseFullName | Should -BeNullOrEmpty
        }

        It 'reports None for an empty statement list' {
            (Resolve-SqlStatementTarget -Statement @() -OptionList $Script:OptionList).Status | Should -Be "None"
        }

        It 'reports None for a null statement list' {
            (Resolve-SqlStatementTarget -Statement $null -OptionList $Script:OptionList).Status | Should -Be "None"
        }
    }

    Context 'a resolved database (criteria 1, 2, 6, 7)' {
        It 'annotates the statement with its connection and strips the prefix' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [ODW].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Ok"
            $Result.Statement.Count | Should -Be 1
            $Result.Statement[0].DataConnectionDoId | Should -Be "2003044"
            $Result.Statement[0].DatabaseName | Should -Be "ODW"
            $Result.Statement[0].Text | Should -Be "SELECT * FROM [dbo].[Person]"
        }

        It 'resolves the name whatever the dropdown has selected' {
            # The option list is the whole input, so the selection plays no part - which is what
            # makes criterion 2 (the same query under another selection) hold.
            (Resolve-Text -SqlText "SELECT * FROM [oises]..[Person]" -OptionList $Script:OptionList).Statement[0].DataConnectionDoId |
                Should -Be "1001572"
        }

        It 'leaves an unprefixed statement on the selected connection' {
            # $null means "the connection the dropdown has", which the pipeline reads as
            # Context.DataConnectionDoId - so a mixed script does not drag unprefixed statements
            # onto the prefixed one's database.
            $Result = Resolve-Text -SqlText "SELECT * FROM [ODW].[dbo].[A]`r`nSELECT * FROM [dbo].[B]" -OptionList $Script:OptionList
            $Result.Statement[0].DataConnectionDoId | Should -Be "2003044"
            $Result.Statement[1].DataConnectionDoId | Should -BeNullOrEmpty
        }

        It 'does not switch the dropdown, because an inline prefix is not sticky' {
            (Resolve-Text -SqlText "SELECT * FROM [ODW].[dbo].[Person]" -OptionList $Script:OptionList).UseFullName |
                Should -BeNullOrEmpty
        }
    }

    Context 'a script spanning databases, one per statement' {
        # Legal since issue #151: three statements naming three databases is three queries against
        # three connections, not a cross-database join. The first cut of #152 rejected this.
        It 'routes each statement to its own connection' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [OISES].[dbo].[A]`r`nSELECT * FROM [ODW].[dbo].[B]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Ok"
            $Result.Statement.Count | Should -Be 2
            $Result.Statement[0].DataConnectionDoId | Should -Be "1001572"
            $Result.Statement[1].DataConnectionDoId | Should -Be "2003044"
        }

        It 'strips the prefix from every statement' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [OISES].[dbo].[A]`r`nSELECT * FROM [ODW].[dbo].[B]" -OptionList $Script:OptionList
            @($Result.Statement | Where-Object { $_.Text -match "OISES|ODW" }).Count | Should -Be 0
        }

        It 'keeps the statements in editor order' {
            $Result = Resolve-Text -SqlText "SELECT 1 FROM [OISES].[dbo].[A]`r`nSELECT 2 FROM [ODW].[dbo].[B]" -OptionList $Script:OptionList
            @($Result.Statement | ForEach-Object { $_.Ordinal }) | Should -Be @(1, 2)
        }
    }

    Context 'USE (criterion 5, and open question 3)' {
        It 'drops a bare USE and reports the switch, leaving nothing to execute' {
            $Result = Resolve-Text -SqlText "USE [ODW]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Ok"
            $Result.Statement.Count | Should -Be 0
            $Result.UseFullName | Should -Be "ODW - 2003044"
            $Result.UseDatabase | Should -Be "ODW"
            $Result.Message | Should -Match "Nothing to execute"
        }

        It 'applies a USE to every statement after it' {
            $Result = Resolve-Text -SqlText "USE [ODW];`r`nSELECT * FROM [dbo].[A]`r`nSELECT * FROM [dbo].[B]" -OptionList $Script:OptionList
            $Result.Statement.Count | Should -Be 2
            $Result.Statement[0].DataConnectionDoId | Should -Be "2003044"
            $Result.Statement[1].DataConnectionDoId | Should -Be "2003044"
            $Result.UseFullName | Should -Be "ODW - 2003044"
        }

        It 'leaves statements BEFORE the USE on the selected connection' {
            # The sticky switch starts where the USE is, not at the top of the script.
            $Result = Resolve-Text -SqlText "SELECT * FROM [dbo].[A]`r`nUSE [ODW];`r`nSELECT * FROM [dbo].[B]" -OptionList $Script:OptionList
            $Result.Statement.Count | Should -Be 2
            $Result.Statement[0].DataConnectionDoId | Should -BeNullOrEmpty
            $Result.Statement[1].DataConnectionDoId | Should -Be "2003044"
        }

        It 'lets an inline prefix win over the USE in force for that statement only' {
            $Result = Resolve-Text -SqlText "USE [ODW];`r`nSELECT * FROM [OISES].[dbo].[A]`r`nSELECT * FROM [dbo].[B]" -OptionList $Script:OptionList
            $Result.Statement[0].DataConnectionDoId | Should -Be "1001572"
            $Result.Statement[1].DataConnectionDoId | Should -Be "2003044"
        }

        It 'reports the connection in its own casing so the dropdown entry matches' {
            (Resolve-Text -SqlText "USE [odw]" -OptionList $Script:OptionList).UseFullName | Should -Be "ODW - 2003044"
        }
    }

    Context 'rejections, decided before anything is posted (criteria 8, 9, 10)' {
        It 'rejects an unknown database, naming the statement and the available connections' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [Nope].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "Statement 1"
            $Result.Message | Should -Match "Nope"
            $Result.Message | Should -Match "OISES"
            $Result.Message | Should -Match "ODW"
        }

        It 'names the right statement when the unknown database is not the first' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [ODW].[dbo].[A]`r`nSELECT * FROM [Nope].[dbo].[B]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "Statement 2"
        }

        It 'rejects an unknown database differently when no connections are available at all' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [Nope].[dbo].[Person]" -OptionList @()
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "no data connections are available"
        }

        It 'rejects an unknown USE target' {
            (Resolve-Text -SqlText "USE [Nope]" -OptionList $Script:OptionList).Status | Should -Be "Rejected"
        }

        It 'rejects a statement that joins two databases (criterion 8)' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [OISES].[dbo].[X] x JOIN [ODW].[dbo].[Y] y ON 1 = 1" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "Statement 1"
            $Result.Message | Should -Match "more than one database"
        }

        It 'rejects a four-part name (criterion 10)' {
            $Result = Resolve-Text -SqlText "SELECT * FROM [Srv].[ODW].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "Four-part"
        }

        It 'posts nothing: a rejection carries no annotated statements' {
            (Resolve-Text -SqlText "SELECT * FROM [Nope].[dbo].[Person]" -OptionList $Script:OptionList).UseFullName |
                Should -BeNullOrEmpty
        }
    }

    Context 'selection execution (criterion 11)' {
        It 'resolves a selected fragment on its own' {
            # The gate has no notion of a selection: it only ever sees statements, which is why
            # criterion 11 holds. What is asserted is the concrete result for a fragment.
            $Result = Resolve-Text -SqlText "SELECT * FROM [ODW].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Ok"
            $Result.Statement[0].DataConnectionDoId | Should -Be "2003044"
            $Result.Statement[0].Text | Should -Be "SELECT * FROM [dbo].[Person]"
        }

        It 'still rejects a selection whose single statement spans two databases' {
            (Resolve-Text -SqlText "SELECT * FROM [OISES].[dbo].[X] x JOIN [ODW].[dbo].[Y] y ON 1 = 1" -OptionList $Script:OptionList).Status |
                Should -Be "Rejected"
        }
    }
}

Describe 'Resolve-SqlStatementTarget without ScriptDom' {
    It 'reports None so execution falls back to the selected data connection' {
        function Get-SqlDatabaseReference {
            param($SqlText, $ParserVersion)
            return [PSCustomObject]@{ Status = "Unavailable"; Database = @(); UseDatabase = $null; Rejection = $null; Message = $null }
        }

        $Statement = @([PSCustomObject]@{ Ordinal = 1; Text = "SELECT * FROM [ODW].[dbo].[Person]"; StartOffset = 0; Length = 34 })
        (Resolve-SqlStatementTarget -Statement $Statement -OptionList @("ODW - 2003044")).Status | Should -Be "None"
    }
}
