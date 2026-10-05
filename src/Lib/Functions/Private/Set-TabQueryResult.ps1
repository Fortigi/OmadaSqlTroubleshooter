# The Results pane's stack of per-statement results, and the one of them commands act on (issue #151).
#
# The list lives on the tab session and the ItemsControl is a rendering of it - the same arrangement
# QueryMessages uses in Write-TabMessage.ps1, and for the same reason: two tabs can finish a query at
# the same moment, and neither tab's results are reachable from the other whatever
# Set-ActiveTabContext happens to be pointing at when the second completion lands.
#
# There is no named per-result DataGrid to reach. Issue #151 retired that single grid's x:Name when it
# became one grid per statement, and a name inside a DataTemplate would not reach FindName in any case.
# Everything that used to read the named grid off the tab's Elements now asks
# Get-FocusedQueryResultGrid instead.

function Set-TabQueryResult {
    <#
    .SYNOPSIS
    Bind one result per statement into the Results pane, and focus the first of them.

    .DESCRIPTION
    Replaces the single-grid binding Complete-ExecuteQueryResult used to do. Takes the pipeline's
    per-statement outcomes and turns the ones that RETURNED into result items; a statement that failed
    contributes no grid at all, and its error is already in the Messages pane
    (Write-ContainedErrorLog -TabScoped put it there).

    That choice is worth stating because it has a visible consequence: grid positions no longer
    correspond to statement ordinals when something failed. The header carries the ordinal precisely so
    the user can still tell which statement a grid belongs to - "Statement 3" after a gap means
    statement 2 failed, and the Messages pane says how.

    .PARAMETER TabSession
    The tab whose pane to bind. Defaults to the active tab, which during a background completion is the
    tab the work belongs to.

    .PARAMETER StatementOutcome
    The ordered per-statement outcomes from Invoke-OmadaExecutePipeline.

    .OUTPUTS
    The number of rows across every bound result - what the status bar reports for the run.
    #>
    [CmdLetBinding()]
    param(
        $TabSession,
        $StatementOutcome
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target) {
            return 0
        }

        $Private:Result = [System.Collections.Generic.List[object]]::new()
        $Private:TotalRows = 0

        foreach ($Private:Outcome in @($StatementOutcome)) {
            if ($null -eq $Private:Outcome -or $null -ne $Private:Outcome.ErrorRecord -or $null -eq $Private:Outcome.QueryResult) {
                continue
            }

            # Read inside the try, not before it. Omada can answer with JSON keys that are invalid as
            # property names, and it is THIS read that throws when it does - so a read above the try
            # would throw outside it and the repair below would never run. It did, until the context
            # of the two lines was looked at together.
            $Private:Rows = @()
            try {
                $Private:Rows = @($Private:Outcome.QueryResult.d.Rows)
            }
            catch {
                $Private:Rows = @(($Private:Outcome.QueryResult | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10).d.Rows)
            }

            if (($Private:Rows | Measure-Object).Count -le 0) {
                # A statement that ran and found nothing contributes NO grid, which is exactly what an
                # empty result did before this issue: the pane is cleared rather than filled with an
                # empty box.
                #
                # That does not weaken the issue #44 distinction, it just keeps it where #93 and #117
                # already put it. "Query did not return any results!" goes to the Messages pane, the
                # status bar reads "0 rows", and Complete-ExecuteQueryResult selects Messages for a run
                # with nothing to show - so "ran and returned nothing" stays plainly different from
                # "failed" without the Results pane having to say it too.
                #
                # It is also what keeps a single-statement execute identical to today, which is an
                # acceptance criterion in its own right: binding an empty headed grid would change what
                # every zero-row query has always looked like.
                continue
            }

            $Private:RowCount = [int]$Private:Outcome.QueryResult.d.Records
            $Private:TotalRows = $Private:TotalRows + $Private:RowCount

            $Private:Result.Add([PSCustomObject]@{
                    Ordinal     = $Private:Outcome.Ordinal
                    # Parenthesised deliberately: inside a hashtable literal the comma of a -f
                    # argument list is read as the separator between hashtable entries, which leaves
                    # the format call dangling and mis-nests every brace after it.
                    Header      = ("Statement {0}  -  {1:n0} row(s)" -f $Private:Outcome.Ordinal, $Private:RowCount)
                    Rows        = $Private:Rows
                    RowCount    = $Private:RowCount
                    # The "d.rows" wrapper the export and Out-GridView paths already consume unchanged.
                    QueryResult = $Private:Outcome.QueryResult
                })
        }

        $Private:Target.QueryResults = $Private:Result
        # First result, per the agreed default: the menu and the toolbar buttons always have a target,
        # which is what keeps a single-statement execute behaving as it did before this issue - where
        # there was never an "I have not clicked anything yet" state to be in.
        $Private:Target.FocusedQueryResultIndex = 0

        if ($null -ne $Private:Target.Elements -and $null -ne $Private:Target.Elements.ItemsControlQueryResults) {
            # $null rather than an empty list when there is nothing to show: an ItemsControl bound to an
            # empty collection still renders its (empty) panel, and the E2E lane asserts a null
            # ItemsSource as "no result".
            if ($Private:Result.Count -eq 0) {
                $Private:Target.Elements.ItemsControlQueryResults.ItemsSource = $null
            }
            else {
                $Private:Target.Elements.ItemsControlQueryResults.ItemsSource = $Private:Result
            }
        }

        return $Private:TotalRows
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
        return 0
    }
}

function Clear-TabQueryResult {
    <#
    .SYNOPSIS
    Empty a tab's Results pane.

    .DESCRIPTION
    What Set-SqlQueryFunctionState used to achieve with DataGridQueryResult.ItemsSource = $null when a
    tab disconnects. Kept as a function rather than inlined because the stack has two halves now - the
    list on the session and the control bound to it - and clearing only one of them leaves the pane
    showing results the session no longer believes in.

    .PARAMETER TabSession
    The tab whose pane to clear. Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target) {
            return
        }

        $Private:Target.QueryResults = [System.Collections.Generic.List[object]]::new()
        $Private:Target.FocusedQueryResultIndex = 0

        if ($null -ne $Private:Target.Elements -and $null -ne $Private:Target.Elements.ItemsControlQueryResults) {
            $Private:Target.Elements.ItemsControlQueryResults.ItemsSource = $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Set-FocusedQueryResult {
    <#
    .SYNOPSIS
    Record which result the user is working in.

    .DESCRIPTION
    Called when a per-result grid takes focus. Every command that used to act on "the" result grid -
    Copy, Copy with Headers, Copy As, Select All, Save Results As, Save Selected As, View Selected,
    Show output and Save output - acts on this one.

    .PARAMETER TabSession
    Defaults to the active tab.

    .PARAMETER Index
    The result's position in the stack. Out-of-range values are ignored rather than clamped: a stale
    index from a previous run would otherwise silently point the commands at the wrong result.
    #>
    [CmdLetBinding()]
    param(
        $TabSession,
        [int]$Index
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.QueryResults) {
            return
        }

        if ($Index -lt 0 -or $Index -ge @($Private:Target.QueryResults).Count) {
            return
        }

        $Private:Target.FocusedQueryResultIndex = $Index
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Get-FocusedQueryResult {
    <#
    .SYNOPSIS
    The result the user is working in, or $null when there is none.

    .DESCRIPTION
    The replacement for $Script:RunTimeData.QueryResult as "the result" for everything the user can act
    on. RunTimeData.QueryResult still holds the FIRST statement's response, for the paths that predate
    issue #151, but it is no longer what Copy or Save output should read - with several results on
    screen that would silently act on the top one.

    .PARAMETER TabSession
    Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.QueryResults) {
            return $null
        }

        $Private:All = @($Private:Target.QueryResults)
        if ($Private:All.Count -eq 0) {
            return $null
        }

        $Private:Index = [int]$Private:Target.FocusedQueryResultIndex
        if ($Private:Index -lt 0 -or $Private:Index -ge $Private:All.Count) {
            $Private:Index = 0
        }

        return $Private:All[$Private:Index]
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
        return $null
    }
}

function Get-FocusedQueryResultGrid {
    <#
    .SYNOPSIS
    The DataGrid showing the focused result, or $null.

    .DESCRIPTION
    The per-result grids are created by the ItemsControl from its DataTemplate, so they have no names
    and cannot be reached through $TabSession.Elements. They are found by asking the item container
    generator for the focused index's container and walking down to the DataGrid inside it.

    A visual-tree walk rather than a name lookup is a real cost - it is fragile to the template's shape
    - which is why the template is deliberately shallow (a two-row Grid holding a header and the grid)
    and why QueryResultContextMenuIsShared.Tests.ps1 asserts that shape.

    Returns $null when the containers have not been generated yet. That is not an error: a command
    cannot act on a grid that has not been realised, and every caller already guards for no selection.

    .PARAMETER TabSession
    Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.Elements) {
            return $null
        }

        $Private:Items = $Private:Target.Elements.ItemsControlQueryResults
        if ($null -eq $Private:Items -or $Private:Items.Items.Count -eq 0) {
            return $null
        }

        $Private:Index = [int]$Private:Target.FocusedQueryResultIndex
        if ($Private:Index -lt 0 -or $Private:Index -ge $Private:Items.Items.Count) {
            $Private:Index = 0
        }

        $Private:Container = $Private:Items.ItemContainerGenerator.ContainerFromIndex($Private:Index)
        if ($null -eq $Private:Container) {
            return $null
        }

        return Find-VisualChildDataGrid -Parent $Private:Container
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
        return $null
    }
}

function Find-VisualChildDataGrid {
    <#
    .SYNOPSIS
    The first DataGrid in an element's visual subtree, or $null.

    .DESCRIPTION
    Breadth-first rather than recursive: the grid sits two levels down in the result template, and a
    recursive walk would descend into the whole of the first branch - including a populated grid's
    rows - before looking at the second.

    .PARAMETER Parent
    The element to search under.
    #>
    [CmdLetBinding()]
    param(
        $Parent
    )

    if ($null -eq $Parent) {
        return $null
    }

    $Private:Queue = [System.Collections.Generic.Queue[object]]::new()
    $Private:Queue.Enqueue($Parent)

    while ($Private:Queue.Count -gt 0) {
        $Private:Node = $Private:Queue.Dequeue()
        $Private:Count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Private:Node)

        for ($Private:Index = 0; $Private:Index -lt $Private:Count; $Private:Index++) {
            $Private:Child = [System.Windows.Media.VisualTreeHelper]::GetChild($Private:Node, $Private:Index)
            if ($Private:Child -is [System.Windows.Controls.DataGrid]) {
                return $Private:Child
            }

            $Private:Queue.Enqueue($Private:Child)
        }
    }

    return $null
}
