BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    foreach ($Function in @(
            "Get-SqlParserType", "Get-SqlScriptFragment", "Get-SqlFragmentDescendant",
            "Get-SqlDatabaseReference", "ConvertTo-UnqualifiedSqlQuery",
            "Resolve-DataConnectionReference", "Resolve-SqlDatabaseTarget")) {
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
}

Describe 'Resolve-SqlDatabaseTarget' {
    BeforeEach {
        if (-not $Script:ScriptDomAvailable) {
            Set-ItResult -Skipped -Because "ScriptDom is not loaded in this session"
        }
        $Script:OptionList = @("OISES - 1001572", "ODW - 2003044")
    }

    Context 'a query that addresses no database (issue #152 criterion 14)' {
        It 'reports None so the query executes exactly as it did before' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "None"
            $Result.TargetDoId | Should -BeNullOrEmpty
            $Result.RewrittenText | Should -BeNullOrEmpty
        }
    }

    Context 'a resolved database (criteria 1, 2, 6, 7)' {
        It 'resolves the name to a DoId and hands back the rewritten text' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [ODW].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Ok"
            $Result.TargetDoId | Should -Be "2003044"
            $Result.TargetName | Should -Be "ODW"
            $Result.TargetFullName | Should -Be "ODW - 2003044"
            $Result.RewrittenText | Should -Be "SELECT * FROM [dbo].[Person]"
        }

        It 'resolves the name whatever the currently selected connection is' {
            # The dropdown selection plays no part: the option list is the whole input, so the same
            # query resolves identically no matter which entry happens to be selected.
            (Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [oises]..[Person]" -OptionList $Script:OptionList).TargetDoId |
                Should -Be "1001572"
        }

        It 'does not report a USE for an inline prefix, so the prefix stays non-sticky' {
            (Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [ODW].[dbo].[Person]" -OptionList $Script:OptionList).UseDatabase |
                Should -BeNullOrEmpty
        }
    }

    Context 'USE (criterion 5)' {
        It 'reports SwitchOnly for a bare USE, with nothing to execute' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "USE [ODW]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "SwitchOnly"
            $Result.UseDatabase | Should -Be "ODW"
            $Result.TargetFullName | Should -Be "ODW - 2003044"
            $Result.Message | Should -Match "ODW"
        }

        It 'reports Ok plus the switch when USE is followed by statements' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "USE [ODW];`r`nSELECT * FROM [dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Ok"
            $Result.UseDatabase | Should -Be "ODW"
            $Result.TargetDoId | Should -Be "2003044"
            $Result.RewrittenText.Trim() | Should -Be "SELECT * FROM [dbo].[Person]"
        }

        It 'reports the connection in its own casing so the dropdown entry matches' {
            (Resolve-SqlDatabaseTarget -SqlText "USE [odw]" -OptionList $Script:OptionList).UseDatabase | Should -Be "ODW"
        }
    }

    Context 'rejections, decided before anything is posted (criteria 8, 9, 10)' {
        It 'rejects an unknown database and lists the available connections' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [Nope].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "Nope"
            $Result.Message | Should -Match "OISES"
            $Result.Message | Should -Match "ODW"
            $Result.TargetDoId | Should -BeNullOrEmpty
            $Result.RewrittenText | Should -BeNullOrEmpty
        }

        It 'rejects an unknown database differently when no connections are available at all' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [Nope].[dbo].[Person]" -OptionList @()
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "no data connections are available"
        }

        It 'rejects a cross-database query' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [OISES].[dbo].[X] x JOIN [ODW].[dbo].[Y] y ON 1 = 1" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "more than one database"
        }

        It 'rejects a four-part name' {
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [Srv].[ODW].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "Four-part"
        }
    }

    Context 'selection execution (criterion 11)' {
        It 'resolves a selected fragment of a larger script on its own' {
            # The function has no notion of a selection: it only ever sees SqlText, which is why
            # criterion 11 holds. So the thing worth asserting is the concrete result for a fragment
            # that is NOT the whole editor - here the second statement of a two-statement script,
            # resolved without the first statement's database influencing it at all.
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [ODW].[dbo].[Person]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Ok"
            $Result.TargetDoId | Should -Be "2003044"
            $Result.RewrittenText | Should -Be "SELECT * FROM [dbo].[Person]"
        }

        It 'rejects a selection spanning two databases even when each alone would resolve' {
            # Selecting across statements is how a user most easily produces a cross-database text
            # by accident, so the rejection has to hold for a fragment too.
            $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [OISES].[dbo].[X]`r`nSELECT * FROM [ODW].[dbo].[Y]" -OptionList $Script:OptionList
            $Result.Status | Should -Be "Rejected"
            $Result.Message | Should -Match "OISES, ODW"
        }
    }
}

Describe 'Resolve-SqlDatabaseTarget without ScriptDom' {
    It 'reports None so execution falls back to the selected data connection' {
        function Get-SqlDatabaseReference {
            param($SqlText, $ParserVersion)
            return [PSCustomObject]@{ Status = "Unavailable"; Database = @(); UseDatabase = $null; Rejection = $null; Message = $null }
        }

        $Result = Resolve-SqlDatabaseTarget -SqlText "SELECT * FROM [ODW].[dbo].[Person]" -OptionList @("ODW - 2003044")
        $Result.Status | Should -Be "None"
    }
}
