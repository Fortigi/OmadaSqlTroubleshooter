# The sizing of the Results pane's stacked grids (issue #151).
#
# Measured in code rather than expressed in markup, because no WPF layout primitive says "divide the
# available height equally until a floor, then stop dividing and let the parent scroll". StackPanel
# gives every child its NATURAL height and UniformGrid divides equally with no floor at all.
#
# Measured on the real markup in an STA host, two results of 3 and 40 rows in a 1000x600 window, with
# nothing setting a height:
#     result 1 grid 75.2    result 2 grid 706.05    viewport 61.04    extent 833.17
# which is the problem in one line: the 40-row grid renders all forty rows instead of taking a share,
# and the pane scrolls past the first result rather than showing both. That is acceptance criteria 5,
# 7 and 8 all failing at once, and it is why this pass exists.

function Get-QueryResultGridHeight {
    <#
    .SYNOPSIS
    The height one result grid should get: an equal share of the pane, but never less than the floor.

    .DESCRIPTION
    Deliberately pure - no WPF, no measuring, just the arithmetic - so the rule itself is testable in
    the headless CI lane where System.Windows cannot be loaded. The measuring half lives in
    Update-QueryResultStackLayout, which cannot be tested there and is covered by the STA suite
    instead.

    The three behaviours it encodes, which are three acceptance criteria:

      - several results share the pane equally          (equal share)
      - no result is ever shorter than its floor        (five data rows plus the column header)
      - ONE result gets the whole viewport              (equal share == viewport, and a single
                                                         fitting result's floor is below it, so the
                                                         max is the viewport and nothing scrolls)

    When the floor wins, the sum of the heights exceeds the viewport and the pane's own ScrollViewer
    scrolls - which is the fourth criterion, and it needs no code because it falls out of the heights.

    .PARAMETER ViewportHeight
    The height available to the stack.

    .PARAMETER ResultCount
    How many results are on screen.

    .PARAMETER FloorHeight
    The measured minimum for one result: its column header plus five data rows.

    .OUTPUTS
    [double] the height to give each grid, or 0 when there is nothing to size.
    #>
    [CmdLetBinding()]
    param(
        [double]$ViewportHeight,
        [int]$ResultCount,
        [double]$FloorHeight
    )

    if ($ResultCount -le 0) {
        return 0
    }

    # A viewport that has not been measured yet (0, or NaN from an unarranged element) must not produce
    # a height of 0 and collapse every grid to nothing. The floor is the honest answer: it is the least
    # a result is allowed to be, and the next layout pass will widen it.
    if ($ViewportHeight -le 0 -or [double]::IsNaN($ViewportHeight)) {
        return $FloorHeight
    }

    $Share = $ViewportHeight / $ResultCount

    if ($Share -lt $FloorHeight) {
        return $FloorHeight
    }

    return $Share
}

function Get-QueryResultGridFloor {
    <#
    .SYNOPSIS
    The measured height of one grid's column header plus five data rows.

    .DESCRIPTION
    Measured from the grid itself rather than calculated from a font size. Row height is not fixed -
    the grids use Consolas with auto-generated columns, and a cell's content decides its height - so a
    hard-coded number would be wrong the first time anything about the styling changed.

    Measured on a real DataGrid in an STA host: a row arranged to 17.05 and the column header to
    22.05, giving a floor of 107.3. Those are the numbers this returns, not numbers it assumes.

    Falls back to an estimate when the grid has no rows to measure - an empty result still needs a
    floor for its header - and to a conservative constant when neither is available. A floor that is
    slightly wrong still shows a usable grid; a floor of zero collapses it.

    .PARAMETER DataGrid
    The grid to measure. Its rows must already be generated, which means after a layout pass.

    .PARAMETER RowCount
    How many data rows the floor should cover. Five, per the acceptance criterion.

    .OUTPUTS
    [double] the floor height.
    #>
    [CmdLetBinding()]
    param(
        $DataGrid,
        [int]$RowCount = 5
    )

    # Last resort only: roughly five rows plus a header at the default font size, used when there is
    # nothing measurable at all.
    $Private:Fallback = 110.0

    if ($null -eq $DataGrid) {
        return $Private:Fallback
    }

    try {
        $Private:RowHeight = 0.0
        $Private:Container = $DataGrid.ItemContainerGenerator.ContainerFromIndex(0)
        if ($null -ne $Private:Container -and $Private:Container.ActualHeight -gt 0) {
            $Private:RowHeight = [double]$Private:Container.ActualHeight
        }
        elseif ($DataGrid.FontSize -gt 0) {
            # No row to measure (an empty result). The font's line height plus the cell padding the
            # default DataGridCell applies is the closest honest estimate.
            $Private:RowHeight = [double]$DataGrid.FontSize * 1.4
        }

        $Private:HeaderHeight = 0.0
        $Private:Presenter = Find-VisualChildColumnHeadersPresenter -Parent $DataGrid
        if ($null -ne $Private:Presenter -and $Private:Presenter.ActualHeight -gt 0) {
            $Private:HeaderHeight = [double]$Private:Presenter.ActualHeight
        }
        elseif ($DataGrid.ColumnHeaderHeight -gt 0 -and -not [double]::IsNaN($DataGrid.ColumnHeaderHeight)) {
            $Private:HeaderHeight = [double]$DataGrid.ColumnHeaderHeight
        }

        if ($Private:RowHeight -le 0) {
            return $Private:Fallback
        }

        return $Private:HeaderHeight + ($RowCount * $Private:RowHeight)
    }
    catch {
        return $Private:Fallback
    }
}

function Find-VisualChildColumnHeadersPresenter {
    <#
    .SYNOPSIS
    A DataGrid's column headers presenter, or $null.

    .DESCRIPTION
    The header's height is not a property of the grid - ColumnHeaderHeight is NaN unless something set
    it - so the only way to know how tall the header actually is, is to find the element that renders
    it.

    .PARAMETER Parent
    The grid to search under.
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
            if ($Private:Child -is [System.Windows.Controls.Primitives.DataGridColumnHeadersPresenter]) {
                return $Private:Child
            }

            $Private:Queue.Enqueue($Private:Child)
        }
    }

    return $null
}

function Register-QueryResultPaneResizeHandler {
    <#
    .SYNOPSIS
    Sizes the result grids again whenever the Results pane's height changes.

    .DESCRIPTION
    The sizing pass gives every grid a fixed height from the pane's viewport. Run only after an
    execute, that height went stale as soon as the pane changed size - a window restore or resize, the
    editor/output splitter dragged - and one result no longer fitted: an outer scrollbar appeared and
    the grid's own horizontal scrollbar sat below the visible pane.

    Subscribes to the pane's SizeChanged once per pane; a second call does nothing, marked by the
    ScrollViewer's Tag, which nothing else uses. Only a HEIGHT change re-sizes: a width change cannot
    alter a grid's share, and the sizing pass itself never changes the pane's height (it changes the
    extent, and through the vertical scrollbar the viewport width), so the handler cannot feed itself.

    The pass is deferred to the dispatcher at Background priority, not run inside SizeChanged. The
    ScrollViewer updates ViewportHeight in its LayoutUpdated callback, which runs AFTER SizeChanged, so
    a pass run in the handler read the viewport from before the resize and was always one resize
    behind - measured in the STA probe. By Background priority layout has finished.

    Bare scriptblocks rather than closures, for the reason Complete-ExecuteQueryResult gives:
    GetNewClosure loses the module's commands. The resized pane travels as the dispatcher operation's
    argument, and the tab is resolved from it.

    .PARAMETER TabSession
    The tab whose pane to watch.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    $Private:Scroll = $TabSession.Elements.ScrollViewerQueryResults
    if ($null -eq $Private:Scroll -or $Private:Scroll.Tag -eq "QueryResultPaneResize") {
        return
    }

    $Private:Scroll.Tag = "QueryResultPaneResize"
    $Private:Scroll.Add_SizeChanged({
            param($EventSender, $SizeChangedEventArgs)

            if ($SizeChangedEventArgs.HeightChanged) {
                [void]$EventSender.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [System.Action[object]] {
                        param($ResizedPane)
                        Invoke-QueryResultPaneResize -ScrollViewer $ResizedPane
                    },
                    $EventSender)
            }
        })
}

function Invoke-QueryResultPaneResize {
    <#
    .SYNOPSIS
    Re-sizes the result grids of the tab whose Results pane changed height.

    .DESCRIPTION
    The tab is the one whose ScrollViewerQueryResults IS the resized control, not whichever tab is
    active: a tab's pane is laid out, and so resized, as it is being shown, which can be before the
    active tab has been switched to it.

    Best effort, like the sizing pass itself: a pane that could not be re-sized still shows its
    results, so a failure is logged rather than reported. This runs on every height change while a
    window is being dragged.

    .PARAMETER ScrollViewer
    The resized pane.
    #>
    [CmdLetBinding()]
    param(
        $ScrollViewer
    )

    try {
        $Private:Owner = @($Script:Tabs | Where-Object { [object]::ReferenceEquals($_.Elements.ScrollViewerQueryResults, $ScrollViewer) }) | Select-Object -First 1
        if ($null -ne $Private:Owner) {
            Update-QueryResultStackLayout -TabSession $Private:Owner
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Update-QueryResultStackLayout {
    <#
    .SYNOPSIS
    Give every result grid an explicit height, so the stack shares the pane and never collapses.

    .DESCRIPTION
    Runs after the results are bound (Complete-ExecuteQueryResult) and again whenever the pane's height
    changes (the SizeChanged handler Register-QueryResultPaneResizeHandler adds). Without the second, a
    pane that got smaller after an execute kept the grid at its old height, which brought in an outer
    scrollbar and put the grid's own horizontal scrollbar below the visible pane. Sets an explicit Height on
    each grid, which is the only way the stack behaves: inside a StackPanel a grid with
    VerticalAlignment="Stretch" has nothing to stretch to, because the panel offers its children
    infinite height along the stack axis and then takes their desired size.

    EVERY count is driven through here, including one. Special-casing a single result in markup is the
    trap: it would get its natural height - all its rows - instead of the pane's, and "a single result
    must look exactly as it does today" would break while looking like it had been handled.

    .PARAMETER TabSession
    The tab whose pane to size. Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.Elements) {
            return
        }

        $Private:Items = $Private:Target.Elements.ItemsControlQueryResults
        $Private:Scroll = $Private:Target.Elements.ScrollViewerQueryResults
        if ($null -eq $Private:Items -or $null -eq $Private:Scroll) {
            return
        }

        $Private:Count = $Private:Items.Items.Count
        if ($Private:Count -le 0) {
            return
        }

        # The containers have to exist before anything can be measured or sized. They do not, on the
        # same pass that assigned ItemsSource, so a caller that has just bound results must let the
        # layout run first - Complete-ExecuteQueryResult does that through the dispatcher.
        $Private:Grid = [System.Collections.Generic.List[object]]::new()
        for ($Private:Index = 0; $Private:Index -lt $Private:Count; $Private:Index++) {
            $Private:Container = $Private:Items.ItemContainerGenerator.ContainerFromIndex($Private:Index)
            if ($null -eq $Private:Container) {
                continue
            }

            $Private:Found = Find-VisualChildDataGrid -Parent $Private:Container
            if ($null -ne $Private:Found) {
                $Private:Grid.Add($Private:Found)
            }
        }

        if ($Private:Grid.Count -eq 0) {
            return
        }

        # One floor for the run, measured from the first grid that has rows. Per-grid floors would let
        # two results of the same statement count end up different heights, which reads as a rendering
        # fault rather than a rule.
        $Private:Measurable = @($Private:Grid | Where-Object { $_.Items.Count -gt 0 } | Select-Object -First 1)
        $Private:Floor = Get-QueryResultGridFloor -DataGrid $(if ($Private:Measurable.Count -gt 0) { $Private:Measurable[0] } else { $Private:Grid[0] })

        # The header above each grid is part of the item, not of the grid, so the height available to
        # the GRIDS is the viewport less what the headers take.
        $Private:HeaderAllowance = 0.0
        $Private:FirstContainer = $Private:Items.ItemContainerGenerator.ContainerFromIndex(0)
        if ($null -ne $Private:FirstContainer -and $Private:FirstContainer.ActualHeight -gt 0 -and $Private:Grid[0].ActualHeight -gt 0) {
            $Private:HeaderAllowance = [math]::Max(0.0, [double]$Private:FirstContainer.ActualHeight - [double]$Private:Grid[0].ActualHeight)
        }

        $Private:Available = [double]$Private:Scroll.ViewportHeight - ($Private:HeaderAllowance * $Private:Grid.Count)
        $Private:Height = Get-QueryResultGridHeight -ViewportHeight $Private:Available -ResultCount $Private:Grid.Count -FloorHeight $Private:Floor

        foreach ($Private:Each in $Private:Grid) {
            # A height the USER dragged is left alone (issue #151 feedback). Register-QueryResultGridHandler
            # marks a grid as user-sized when its splitter finishes a drag, and the mark is cleared
            # when Set-TabQueryResult rebinds - so a drag survives pane resizes and the automatic
            # equal-share sizing resumes on the next execute, which is the agreed behaviour.
            if ($Private:Each.Tag -is [hashtable] -and $Private:Each.Tag.UserSized) {
                continue
            }

            $Private:Each.Height = $Private:Height
        }

        "Sized {0} result grid(s) to {1:n1} (floor {2:n1}, viewport {3:n1})" -f $Private:Grid.Count, $Private:Height, $Private:Floor, $Private:Scroll.ViewportHeight | Write-LogOutput -LogType VERBOSE
    }
    catch {
        # A pane that could not be sized still shows its results at their natural height, which is worse
        # than the rule but far better than an exception on every execute.
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
