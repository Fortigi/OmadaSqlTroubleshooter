#Requires -Version 7.0
# The Messages pane reports each statement's rows and its own elapsed time, then the run totals
# (issue #151).
#
# This exists because the per-statement half was NOT implemented when the acceptance criterion was
# first ticked. The grids, the state, the sizing and the handlers were all built; Write-TabExecuteSummary
# still wrote one "Rows read" and one "Completion time" for the whole run, and the PR body claimed
# "two result grids and two summary lines". Only hands-on testing found it. These assertions are what
# make the claim checkable.
#
# The shape the issue asks for, from the SSMS screenshots in its body:
#
#     Statement 1: 3 row(s) in 00:00:00.412
#     Statement 2: 49 row(s) in 00:00:01.004
#     Rows read: 52
#     Completion time: 00:00:01.416

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Format-ElapsedTime.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-TabMessage.ps1")

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

    function Get-ActiveTabSession { return $Script:TestTabSession }

    function script:New-TestTabSession {
        return [pscustomobject]@{
            Id            = "tab-A"
            Elements      = @{
                TextBoxQueryMessages  = [pscustomobject]@{ Text = "" }
                TabControlQueryOutput = [pscustomobject]@{ SelectedIndex = 0 }
            }
            QueryMessages = [System.Collections.Generic.List[string]]::new()
        }
    }

    function script:New-StatementOutcome {
        param(
            [int]$Ordinal,
            [int]$RowCount = 2,
            $ErrorRecord = $null,
            [string]$Elapsed = "00:00:00.5000000"
        )

        $Private:Result = $null
        if ($null -eq $ErrorRecord) {
            $Private:Result = [pscustomobject]@{ d = [pscustomobject]@{ Records = $RowCount; Rows = @(1..([math]::Max($RowCount, 0))) } }
        }

        return @{
            Ordinal     = $Ordinal
            Text        = "SELECT $Ordinal"
            QueryResult = $Private:Result
            ErrorRecord = $ErrorRecord
            FailedStep  = $(if ($null -ne $ErrorRecord) { "ExecuteQuery" } else { $null })
            Elapsed     = [TimeSpan]::Parse($Elapsed)
        }
    }

    function script:New-TestErrorRecord {
        param([string]$Message = "statement failed")
        return [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message), "TestFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
    }

    function script:Get-PaneLines {
        return @($Script:TestTabSession.QueryMessages)
    }
}

Describe 'Write-TabExecuteSummary - the per-statement breakdown' -Tag 'Unit' {

    BeforeEach {
        $Script:TestTabSession = New-TestTabSession
    }

    Context 'A multi-statement run' {

        It 'writes one line per statement, then the run totals' {
            # The acceptance criterion: "two SELECTs ... produces two result grids and two summary
            # lines."
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 52 -Elapsed "00:00:01.416" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3 -Elapsed "00:00:00.4120000"),
                (New-StatementOutcome -Ordinal 2 -RowCount 49 -Elapsed "00:00:01.0040000")
            )

            $Private:Lines = Get-PaneLines
            @($Private:Lines | Where-Object { $_ -match '^Statement \d' }).Count | Should -Be 2
            @($Private:Lines | Where-Object { $_ -match '^Rows read:' }).Count | Should -Be 1
            @($Private:Lines | Where-Object { $_ -match '^Completion time:' }).Count | Should -Be 1
        }

        It 'reports each statement rows by its own ordinal' {
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 52 -Elapsed "00:00:01.416" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 49)
            )

            $Private:Lines = Get-PaneLines
            ($Private:Lines -join "`n") | Should -Match 'Statement 1: 3 row\(s\)'
            ($Private:Lines -join "`n") | Should -Match 'Statement 2: 49 row\(s\)'
        }

        It 'reports each statement own elapsed time, not the run total' {
            # The feedback this file was written for: a per-statement time, not one number repeated.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 52 -Elapsed "00:00:01.416" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3 -Elapsed "00:00:00.4120000"),
                (New-StatementOutcome -Ordinal 2 -RowCount 49 -Elapsed "00:00:01.0040000")
            )

            $Private:Text = (Get-PaneLines) -join "`n"
            $Private:Text | Should -Match 'Statement 1:.*0\.412|Statement 1:.*00:00:00'
            $Private:Text | Should -Match 'Statement 2:.*1\.004|Statement 2:.*00:00:01'
        }

        It 'keeps the run totals as well as the breakdown' {
            # "Also include total rows as you did now" - the totals are additive, not replaced.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 52 -Elapsed "00:00:01.416" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 49)
            )

            $Private:Text = (Get-PaneLines) -join "`n"
            $Private:Text | Should -Match 'Rows read: 52'
            $Private:Text | Should -Match 'Completion time: 00:00:01\.416'
        }

        It 'puts the breakdown BEFORE the totals' {
            # The SSMS shape in the issue: per-statement lines, then the completion line last.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 52 -Elapsed "00:00:01.416" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 49)
            )

            $Private:Lines = Get-PaneLines
            $Private:LastStatement = [array]::FindLastIndex([string[]]$Private:Lines, [Predicate[string]] { $args[0] -match '^Statement \d' })
            $Private:TotalIndex = [array]::FindIndex([string[]]$Private:Lines, [Predicate[string]] { $args[0] -match '^Rows read:' })

            $Private:LastStatement | Should -BeLessThan $Private:TotalIndex
        }
    }

    Context 'A statement that did not return' {

        It 'says a failed statement failed, rather than reporting zero rows' {
            # Issue #44 held per statement. "Statement 2: 0 row(s)" would read as "it ran and found
            # nothing", which is the one thing that ambiguity must never be confused with.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 3 -Elapsed "00:00:01.000" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -ErrorRecord (New-TestErrorRecord))
            )

            $Private:Text = (Get-PaneLines) -join "`n"
            $Private:Text | Should -Match 'Statement 2: failed'
            $Private:Text | Should -Not -Match 'Statement 2: 0 row'
        }

        It 'still reports a statement that ran and found nothing as zero rows' {
            # The other side of the same distinction: it RAN, so it says so.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 3 -Elapsed "00:00:01.000" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 3),
                (New-StatementOutcome -Ordinal 2 -RowCount 0)
            )

            $Private:Text = (Get-PaneLines) -join "`n"
            $Private:Text | Should -Match 'Statement 2: 0 row\(s\)'
            $Private:Text | Should -Not -Match 'Statement 2: failed'
        }
    }

    Context 'A single-statement run' {

        It 'writes only the two totals, exactly as every execute did before this issue' {
            # A one-statement run has nothing to break down, and adding "Statement 1: ..." would change
            # what every ordinary execute has always shown.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 9 -Elapsed "00:00:00.900" -StatementOutcome @(
                (New-StatementOutcome -Ordinal 1 -RowCount 9)
            )

            $Private:Lines = Get-PaneLines
            @($Private:Lines | Where-Object { $_ -match '^Statement \d' }).Count | Should -Be 0
            @($Private:Lines).Count | Should -Be 2
        }

        It 'writes only the two totals when no outcomes are supplied at all' {
            # The failure paths and every pre-#151 caller take this route.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 0 -Elapsed "00:00:00.100"

            $Private:Lines = Get-PaneLines
            @($Private:Lines).Count | Should -Be 2
            ($Private:Lines -join "`n") | Should -Match 'Rows read: 0'
        }

    }

    Context 'An outcome that carries no elapsed time' {
        # A statement outcome from a caller that predates the per-statement stopwatch. Two statements,
        # deliberately - this belongs with the multi-statement cases, because a breakdown is only
        # written when there is more than one. Placing it under the single-statement context (where it
        # started) made the assertion contradict its own data.

        It 'still writes the breakdown, just without the time clause' {
            $Private:First = New-StatementOutcome -Ordinal 1 -RowCount 3
            $Private:First.Elapsed = $null
            $Private:Second = New-StatementOutcome -Ordinal 2 -RowCount 4
            $Private:Second.Elapsed = $null

            # NOT wrapped in a Should -Not -Throw scriptblock. That wrapper is why this case failed
            # while an identical construction passed everywhere else: Pester invokes the scriptblock
            # in its own scope, so the $Private:-scoped outcomes built above are not visible inside
            # it, the parameter receives two nulls, the filter drops both, and no breakdown is
            # written. The call is made directly and the absence of a throw is proven by the
            # assertions below completing.
            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 7 -Elapsed "00:00:01.000" -StatementOutcome @($Private:First, $Private:Second)

            $Private:Text = (Get-PaneLines) -join "`n"
            $Private:Text | Should -Match 'Statement 1: 3 row\(s\)'
            $Private:Text | Should -Match 'Statement 2: 4 row\(s\)'
        }

        It 'omits the time clause rather than printing an empty one' {
            # Graceful degradation, verified in isolation: "Statement 1: 3 row(s)" with no trailing
            # " in " and no stray separator.
            $Private:First = New-StatementOutcome -Ordinal 1 -RowCount 3
            $Private:First.Elapsed = $null
            $Private:Second = New-StatementOutcome -Ordinal 2 -RowCount 4
            $Private:Second.Elapsed = $null

            Write-TabExecuteSummary -TabSession $Script:TestTabSession -RowsRead 7 -Elapsed "00:00:01.000" -StatementOutcome @($Private:First, $Private:Second)

            @(Get-PaneLines | Where-Object { $_ -match '^Statement 1:' })[0] | Should -Be "Statement 1: 3 row(s)"
        }
    }
}
