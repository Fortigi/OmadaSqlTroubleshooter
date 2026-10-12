#Requires -Version 7.0
# The Results pane's per-statement result stack and the one of them commands act on (issue #151).
#
# These assert the STATE half, which is testable headlessly: building result items from the pipeline's
# statement outcomes, which statements become grids and which do not, the running row total the status
# bar reports, and which result is focused. The rendering half - finding the focused DataGrid in the
# visual tree - needs a real WPF layout pass and is covered by the STA suite instead.
#
# The tab session is a plain object here, as it is in the other per-tab suites: these run in headless
# CI, where System.Windows cannot be resolved, and the list on the session is the source of truth with
# the control as a mere rendering of it (the QueryMessages arrangement in Write-TabMessage.ps1).

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Set-TabQueryResult.ps1")

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

    function Invoke-SanitizeJsonKeys {
        param([Parameter(ValueFromPipeline = $true)]$InputObject)
        process { $InputObject }
    }

    function Get-ActiveTabSession { return $Script:TestTabSession }

    function script:New-TestTabSession {
        # Elements carries only the one control this code touches. An ItemsControl stand-in rather than
        # the real type: ItemsSource is the whole contract these tests care about.
        return [pscustomobject]@{
            Id                      = "tab-A"
            Elements                = @{
                ItemsControlQueryResults = [pscustomobject]@{ ItemsSource = "previous" }
            }
            QueryResults            = $null
            FocusedQueryResultIndex = 0
        }
    }

    function script:New-StatementOutcome {
        # The shape Invoke-OmadaExecutePipeline returns per statement.
        param(
            [int]$Ordinal,
            [string]$Text = "SELECT 1",
            [int]$RowCount = 2,
            $ErrorRecord = $null,
            [switch]$NoResult
        )

        $Private:Result = $null
        if (-not $NoResult) {
            $Private:Rows = @(1..$RowCount | ForEach-Object { [pscustomobject]@{ Col1 = "v$_" } })
            if ($RowCount -eq 0) { $Private:Rows = @() }
            $Private:Result = [pscustomobject]@{ d = [pscustomobject]@{ Records = $RowCount; Rows = $Private:Rows } }
        }

        return @{
            Ordinal     = $Ordinal
            Text        = $Text
            QueryResult = $Private:Result
            ErrorRecord = $ErrorRecord
            FailedStep  = $(if ($null -ne $ErrorRecord) { "ExecuteQuery" } else { $null })
        }
    }

    function script:New-TestErrorRecord {
        param([string]$Message = "statement failed")
        return [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message), "TestFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
    }
}

Describe 'Set-TabQueryResult' -Tag 'Unit' {

    BeforeEach {
        $Script:TestTabSession = New-TestTabSession
    }

    Context 'Building one result per statement' {

        It 'builds a result for every statement that returned' {
            # The acceptance criterion at the binding: two SELECTs produce two result grids.
            $Private:Total = Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 49)
            )

            @($Script:TestTabSession.QueryResults).Count | Should -Be 2
            $Private:Total | Should -Be 52
        }

        It 'keeps the results in editor order, labelled by statement ordinal' {
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 49)
            ) | Out-Null

            @($Script:TestTabSession.QueryResults | ForEach-Object { $_.Ordinal }) | Should -Be @(1, 2)
        }

        It 'names each result by its statement ordinal and row count' {
            # The header is how the user tells which statement a grid belongs to, and it is the only
            # thing that does so once a failed statement has left a gap in the stack.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3)
            ) | Out-Null

            $Script:TestTabSession.QueryResults[0].Header | Should -Match 'Statement 1'
            $Script:TestTabSession.QueryResults[0].Header | Should -Match '3'
        }

        It 'carries the d.rows wrapper through unchanged, for the export paths' {
            # Save-QueryResultToFile, Export-QueryResultFile and Show-QueryResultGridView all consume
            # that shape. Reshaping it here would break every one of them silently.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 2)
            ) | Out-Null

            $Script:TestTabSession.QueryResults[0].QueryResult.d.Records | Should -Be 2
            @($Script:TestTabSession.QueryResults[0].QueryResult.d.Rows).Count | Should -Be 2
        }

        It 'binds the results to the pane' {
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 2)
            ) | Out-Null

            @($Script:TestTabSession.Elements.ItemsControlQueryResults.ItemsSource).Count | Should -Be 1
        }

        It 'reports the total row count across every statement, for the status bar' {
            # "The status bar reports total rows and total elapsed time for the run."
            $Private:Total = Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 10),
                (New-StatementOutcome -Ordinal 2 -RowCount 5),
                (New-StatementOutcome -Ordinal 3 -RowCount 1)
            )

            $Private:Total | Should -Be 16
        }
    }

    Context 'A statement that did not return' {

        It 'gives a failed statement no grid at all' {
            # The agreed behaviour: a failure contributes no result, and its error is already in the
            # Messages pane. Two statements, one failed, leaves one grid.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -ErrorRecord (New-TestErrorRecord) -NoResult)
            ) | Out-Null

            @($Script:TestTabSession.QueryResults).Count | Should -Be 1
            $Script:TestTabSession.QueryResults[0].Ordinal | Should -Be 1
        }

        It 'keeps the surviving statements ordinals, so a gap is visible rather than silent' {
            # Statement 2 failed, so the stack holds 1 and 3. The headers say so - without the ordinal
            # the user would see two grids and have no way to know which statements they came from.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -ErrorRecord (New-TestErrorRecord) -NoResult),
                (New-StatementOutcome -Ordinal 3 -RowCount 7)
            ) | Out-Null

            @($Script:TestTabSession.QueryResults | ForEach-Object { $_.Ordinal }) | Should -Be @(1, 3)
        }

        It 'gives no grid to a statement that ran and found nothing' {
            # An empty result clears the pane rather than filling it with an empty box - exactly what
            # every zero-row query did before this issue, which is what keeps a single-statement
            # execute identical to today.
            #
            # Issue #44's distinction is not lost, only kept where #93 and #117 already put it:
            # "Query did not return any results!" in the Messages pane, "0 rows" on the status bar,
            # and Complete-ExecuteQueryResult selecting Messages for a run with nothing to show. So
            # "ran and returned nothing" stays plainly different from "failed" without the Results
            # pane having to say it as well.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 0)
            ) | Out-Null

            @($Script:TestTabSession.QueryResults).Count | Should -Be 0
            $Script:TestTabSession.Elements.ItemsControlQueryResults.ItemsSource | Should -BeNullOrEmpty
        }

        It 'binds only the statements that returned, in a run where one found nothing' {
            # The multi-statement consequence, stated so it is a decision rather than a side effect:
            # statement 2 ran and returned nothing, so the stack holds 1 and 3. The ordinals in the
            # headers are what tell the user which statements these are.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 0),
                (New-StatementOutcome -Ordinal 3 -RowCount 7)
            ) | Out-Null

            @($Script:TestTabSession.QueryResults | ForEach-Object { $_.Ordinal }) | Should -Be @(1, 3)
        }

        It 'counts only the rows that were actually returned' {
            # A zero-row statement contributes nothing to the total, so the status bar reports what the
            # run really produced.
            $Private:Total = Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 0)
            )

            $Private:Total | Should -Be 3
        }

        It 'excludes a statement that was never run at all' {
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -NoResult)
            ) | Out-Null

            @($Script:TestTabSession.QueryResults).Count | Should -Be 1
        }

        It 'clears the pane when nothing returned, rather than binding an empty list' {
            # The E2E lane asserts a null ItemsSource as "no result", and an ItemsControl bound to an
            # empty collection still renders its panel.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -ErrorRecord (New-TestErrorRecord) -NoResult)
            ) | Out-Null

            $Script:TestTabSession.Elements.ItemsControlQueryResults.ItemsSource | Should -BeNullOrEmpty
            @($Script:TestTabSession.QueryResults).Count | Should -Be 0
        }

        It 'reports zero rows when every statement failed' {
            $Private:Total = Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -ErrorRecord (New-TestErrorRecord) -NoResult)
            )

            $Private:Total | Should -Be 0
        }
    }

    Context 'Focus after an execute' {

        It 'focuses the first result, so the commands always have a target' {
            # The agreed default. It is also what keeps a single-statement execute behaving as it did
            # before this issue, where there was no "nothing clicked yet" state to be in.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 4)
            ) | Out-Null

            $Script:TestTabSession.FocusedQueryResultIndex | Should -Be 0
            (Get-FocusedQueryResult -TabSession $Script:TestTabSession).Ordinal | Should -Be 1
        }

        It 'resets focus on the next execute rather than keeping a stale index' {
            # A focus of 2 against a one-result run would point the commands at nothing.
            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 1),
                (New-StatementOutcome -Ordinal 2 -RowCount 1),
                (New-StatementOutcome -Ordinal 3 -RowCount 1)
            ) | Out-Null
            Set-FocusedQueryResult -TabSession $Script:TestTabSession -Index 2
            $Script:TestTabSession.FocusedQueryResultIndex | Should -Be 2

            Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 1)
            ) | Out-Null

            $Script:TestTabSession.FocusedQueryResultIndex | Should -Be 0
        }
    }
}

Describe 'Get-FocusedQueryResult' -Tag 'Unit' {

    BeforeEach {
        $Script:TestTabSession = New-TestTabSession
        Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
            (New-StatementOutcome -Ordinal 1 -RowCount 3),
            (New-StatementOutcome -Ordinal 2 -RowCount 49)
        ) | Out-Null
    }

    It 'returns the result the user is working in' {
        Set-FocusedQueryResult -TabSession $Script:TestTabSession -Index 1

        (Get-FocusedQueryResult -TabSession $Script:TestTabSession).Ordinal | Should -Be 2
    }

    It 'defaults to the active tab when none is named' {
        # Every command reaches it this way; during a background completion the active tab is the tab
        # the work belongs to.
        (Get-FocusedQueryResult).Ordinal | Should -Be 1
    }

    It 'returns nothing when there are no results' {
        $Private:Empty = New-TestTabSession

        Get-FocusedQueryResult -TabSession $Private:Empty | Should -BeNullOrEmpty
    }

    It 'falls back to the first result when the index is out of range' {
        # Defensive rather than theoretical: the index lives on the session and the results are
        # replaced on every execute, so the two can disagree for one frame.
        $Script:TestTabSession.FocusedQueryResultIndex = 99

        (Get-FocusedQueryResult -TabSession $Script:TestTabSession).Ordinal | Should -Be 1
    }
}

Describe 'Set-FocusedQueryResult' -Tag 'Unit' {

    BeforeEach {
        $Script:TestTabSession = New-TestTabSession
        Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
            (New-StatementOutcome -Ordinal 1 -RowCount 1),
            (New-StatementOutcome -Ordinal 2 -RowCount 1)
        ) | Out-Null
    }

    It 'records the result that took focus' {
        Set-FocusedQueryResult -TabSession $Script:TestTabSession -Index 1

        $Script:TestTabSession.FocusedQueryResultIndex | Should -Be 1
    }

    It 'ignores an index past the end rather than clamping it' {
        # Clamping would silently point the commands at the last result; ignoring leaves them where
        # the user last put them.
        Set-FocusedQueryResult -TabSession $Script:TestTabSession -Index 5

        $Script:TestTabSession.FocusedQueryResultIndex | Should -Be 0
    }

    It 'ignores a negative index' {
        Set-FocusedQueryResult -TabSession $Script:TestTabSession -Index -1

        $Script:TestTabSession.FocusedQueryResultIndex | Should -Be 0
    }
}

Describe 'Clear-TabQueryResult' -Tag 'Unit' {

    BeforeEach {
        $Script:TestTabSession = New-TestTabSession
        Set-TabQueryResult -TabSession $Script:TestTabSession -StatementOutcome @(
            (New-StatementOutcome -Ordinal 1 -RowCount 3)
        ) | Out-Null
    }

    It 'empties both the list and the pane' {
        # Both halves, which is why this is a function rather than an assignment: clearing only the
        # control would leave the pane showing results the session no longer believes in.
        Clear-TabQueryResult -TabSession $Script:TestTabSession

        @($Script:TestTabSession.QueryResults).Count | Should -Be 0
        $Script:TestTabSession.Elements.ItemsControlQueryResults.ItemsSource | Should -BeNullOrEmpty
    }

    It 'resets the focused index' {
        Clear-TabQueryResult -TabSession $Script:TestTabSession

        $Script:TestTabSession.FocusedQueryResultIndex | Should -Be 0
        Get-FocusedQueryResult -TabSession $Script:TestTabSession | Should -BeNullOrEmpty
    }

    It 'does not throw for a tab that never had results' {
        # Reached from Set-SqlQueryFunctionState on disconnect, which can happen before any execute.
        { Clear-TabQueryResult -TabSession (New-TestTabSession) } | Should -Not -Throw
    }
}
