#Requires -Version 7.0
# The export filename carries the statement number for a multi-statement run (issue #151).
#
#   SqlQuery_<QueryId>_<QueryName>_<DataConnection>_<Tenant>_Statement<N>_Output.<ext>
#
# Two decisions this asserts, both agreed rather than inferred:
#
#   - the data connection STAYS in the name. Removing it would change the filename for every export
#     that predates this issue, which anyone scripting against these names would notice.
#   - the Statement token appears ONLY when more than one result is bound. A single-statement export
#     keeps the exact name it has today, which is the rule the whole feature follows.
#
# The number is the statement's ORDINAL, not its position in the stack: a run where statement 2 failed
# exports statements 1 and 3 as Statement1 and Statement3, so the filename names the statement the
# user actually wrote.
#
# Asserted against the suffix logic rather than by opening a SaveFileDialog - that needs a desktop,
# and what matters here is the name the dialog is handed.

BeforeAll {
    $Script:SourcePath = Join-Path $PSScriptRoot -ChildPath "..\src\Lib\Functions\Private\Save-QueryResultToFile.ps1"
    $Script:Source = Get-Content -Path $Script:SourcePath -Raw

    # The suffix rule, lifted out of the function so it can be exercised without a dialog. Kept
    # deliberately identical to the source: the test below asserts that the source still contains it,
    # so the two cannot drift apart silently.
    function script:Get-StatementSuffix {
        param(
            [int]$ResultCount,
            $FocusedOrdinal
        )

        if ($ResultCount -le 1) {
            return ""
        }

        if ($null -eq $FocusedOrdinal) {
            return ""
        }

        return "_Statement{0}" -f $FocusedOrdinal
    }
}

Describe 'The export filename statement suffix' -Tag 'Unit' {

    Context 'When several statements returned' {

        It 'names the focused statement' {
            Get-StatementSuffix -ResultCount 2 -FocusedOrdinal 2 | Should -Be "_Statement2"
        }

        It 'uses the ordinal rather than the stack position' {
            # Statement 2 failed, so the stack holds ordinals 1 and 3. Exporting the second GRID must
            # produce Statement3, not Statement2 - the filename names the statement, not the slot.
            Get-StatementSuffix -ResultCount 2 -FocusedOrdinal 3 | Should -Be "_Statement3"
        }

        It 'produces the example from the issue feedback' {
            $Private:Name = "SqlQuery_{0}_{1}_{2}_{3}{4}_Output{5}" -f 123456, "TestQuery", "MyConnection", "tenant.omada.cloud", (Get-StatementSuffix -ResultCount 3 -FocusedOrdinal 3), ".json"

            $Private:Name | Should -Be "SqlQuery_123456_TestQuery_MyConnection_tenant.omada.cloud_Statement3_Output.json"
        }
    }

    Context 'When one statement returned' {

        It 'adds no statement token, so the name is what it has always been' {
            Get-StatementSuffix -ResultCount 1 -FocusedOrdinal 1 | Should -Be ""
        }

        It 'leaves a single-statement export byte-identical to the pre-issue name' {
            $Private:Name = "SqlQuery_{0}_{1}_{2}_{3}{4}_Output{5}" -f 123456, "TestQuery", "MyConnection", "tenant.omada.cloud", (Get-StatementSuffix -ResultCount 1 -FocusedOrdinal 1), ".json"

            $Private:Name | Should -Be "SqlQuery_123456_TestQuery_MyConnection_tenant.omada.cloud_Output.json"
        }

        It 'adds no token when nothing is bound at all' {
            Get-StatementSuffix -ResultCount 0 -FocusedOrdinal $null | Should -Be ""
        }

        It 'adds no token when the focused result has no ordinal' {
            Get-StatementSuffix -ResultCount 3 -FocusedOrdinal $null | Should -Be ""
        }
    }
}

Describe 'Save-QueryResultToFile builds the name from that rule' -Tag 'Unit' {

    It 'guards the stack count before adding a statement token' {
        # The "more than one result" condition. Without it every single-statement export would be
        # renamed, which is the behaviour change this rule exists to avoid.
        $Script:Source | Should -Match '\$Private:ResultStack\.Count -gt 1'
    }

    It 'takes the number from the focused result ordinal' {
        $Script:Source | Should -Match '_Statement\{0\}" -f \$Private:FocusedResult\.Ordinal'
    }

    It 'keeps the data connection and the tenant host in the name' {
        # Both agreed to stay: dropping either would change pre-existing export filenames.
        $Script:Source | Should -Match 'CurrentDataConnection\.DisplayName'
        $Script:Source | Should -Match '\[system\.uri\]::New\(\$Script:AppConfig\.BaseUrl\)\.Host'
    }

    It 'places the statement token before _Output in both name formats' {
        # Two format strings - the plain name and the (n) de-duplicating one - and a token added to
        # only one of them would silently drop it the moment a file already existed.
        @([regex]::Matches($Script:Source, '\{3\}\{4\}_Output')).Count | Should -Be 2
    }
}
