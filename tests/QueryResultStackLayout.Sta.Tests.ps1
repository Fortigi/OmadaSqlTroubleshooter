#Requires -Version 7.0
# The Results pane's stacked layout, measured (issue #151).
#
# These are the four acceptance criteria that no headless lane can prove, because they are not about
# arithmetic or markup - they are about what a real WPF measure/arrange pass produces:
#
#   AC 5  two results share the pane height equally
#   AC 6  once the equal share drops below five data rows, every result keeps its header plus five
#         rows and the Results pane itself scrolls
#   AC 7  a result with more rows than its share scrolls inside its own grid
#   AC 8  one result fills the pane with no outer scrollbar
#
# Get-QueryResultGridHeight.Tests.ps1 asserts the RULE in CI. This asserts that the rule, applied to
# the real markup by Update-QueryResultStackLayout, actually comes out on screen.
#
# WHY A CHILD PROCESS. WPF needs an STA thread and PowerShell 7 is MTA, so the measuring runs in a
# `pwsh -STA` child and this file asserts on what it reports back. The alternative - asserting inside
# the parent - silently measures nothing, because ItemContainerGenerator never realises a container on
# an MTA thread.
#
# WHY IT CAN GO INCONCLUSIVE. Loading the whole MainFormTabContent.xaml needs the bundled
# Microsoft.Web.WebView2.Wpf assembly (the markup declares a WebView2 element), which is laid down by
# the psake Dependencies task and is absent on a bare CI runner. A missing assembly or no display is
# not a failing feature, so those runs report inconclusive - the same convention the ScriptDom suites
# use for an offline agent. Set-ItResult rather than -Skip:, because -Skip: is evaluated at discovery
# when the BeforeAll variables are still null.
#
# Measured reference values on this markup, for the numbers below: a DataGridRow arranges to 17.05 and
# a DataGridColumnHeadersPresenter to 22.05, so one result's floor is 22.05 + 5 * 17.05 = 107.3.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:ProbePath = Join-Path $PSScriptRoot "_StaLayoutProbe.ps1"

    $Script:WebView2Assembly = @(
        Join-Path $Script:RepositoryRoot "buildoutput\OmadaSqlTroubleShooter\Bin\WebView2Dlls\win-x64\Microsoft.Web.WebView2.Wpf.dll"
        Join-Path ([System.Environment]::GetFolderPath("LocalApplicationData")) "OmadaSqlTroubleshooter\Bin\Microsoft.Web.WebView2.Wpf.dll"
    ) | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1

    # One child process for the whole file, with every scenario measured in it. Starting a WPF host
    # per test would multiply a ~2s cost by the number of assertions for no extra coverage.
    function script:Invoke-StaLayoutProbe {
        param(
            [Parameter(Mandatory = $true)][string]$AssemblyPath,
            [Parameter(Mandatory = $true)][string]$RepositoryRoot,
            [Parameter(Mandatory = $true)][string]$ProbePath
        )

        $Private:Output = & pwsh -STA -NoProfile -File $ProbePath -RepositoryRoot $RepositoryRoot -AssemblyPath $AssemblyPath 2>&1
        $Private:Text = ($Private:Output | Out-String)

        try {
            return $Private:Text | ConvertFrom-Json
        }
        catch {
            # The raw output is the diagnosis when the child could not produce JSON - a XAML load
            # failure, a missing display, a crashed host - so it is carried into the failure message
            # rather than swallowed.
            return [pscustomobject]@{ Ok = $false; Error = $Private:Text }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Script:WebView2Assembly)) {
        $Script:Measured = Invoke-StaLayoutProbe -AssemblyPath $Script:WebView2Assembly -RepositoryRoot $Script:RepositoryRoot -ProbePath $Script:ProbePath
    }
}

Describe "The Results pane's stacked layout, measured in an STA host" -Tag 'Sta' {

    BeforeEach {
        if ([string]::IsNullOrWhiteSpace($Script:WebView2Assembly)) {
            Set-ItResult -Inconclusive -Because "the bundled WebView2 assembly is not present; run ./build/build.ps1 -Task Dependencies first"
        }
        if ($null -eq $Script:Measured -or -not $Script:Measured.Ok) {
            Set-ItResult -Inconclusive -Because ("the STA layout probe did not report measurements: {0}" -f $Script:Measured.Error)
        }
    }

    Context 'The control itself' {

        It 'loads the whole tab content, so the pane still renders at all' {
            # The broadest thing this file proves, and the one that no other suite can: the markup the
            # stack was cut into still loads as WPF rather than throwing at parse time.
            $Script:Measured.ControlLoaded | Should -BeTrue
        }

        It 'resolves the stack container and its scroll viewer by name' {
            # Which is also what proves the Initialize-FormObject discovery-list addition works: both
            # are found through FindName, exactly as that function finds them.
            $Script:Measured.FoundItemsControl | Should -BeTrue
            $Script:Measured.FoundScrollViewer | Should -BeTrue
        }

        It 'attaches the shared context menu to every per-result grid' {
            # The StaticResource reference reaching into the DataTemplate from the other end of the
            # file. Asserted here because the headless suite can only compare the key against the
            # reference as text.
            $Script:Measured.TwoResults.EveryGridHasContextMenu | Should -BeTrue
        }

        It 'wires the grid handlers to every realised grid' {
            # Register-QueryResultGridHandler replaced nine load-time subscriptions on a single named
            # grid. Nothing headless can see whether they attached, because the grids do not exist
            # until an ItemsControl realises them.
            $Script:Measured.TwoResults.RegisteredCount | Should -Be 2
        }

        It 'gives each grid its own index rather than all of them the last one' {
            # The index each handler reads from its sender's Tag (issue #169), checked through the
            # registration marker. A wrong Tag would make clicking a result focus a different one.
            $Script:Measured.TwoResults.TagsMatchPosition | Should -BeTrue
        }

        It 'numbers the rows of every realised grid' {
            # Issue #151 feedback: the row numbers were missing entirely. The cause was ordering, not
            # the handler - LoadingRow fires during the layout pass that realises the item containers,
            # and these handlers can only attach AFTER that pass, because finding the grids depends on
            # it. Measured before the fix: 6 realised rows, 0 headers set.
            #
            # So the numbers are applied directly to the rows that already exist, and the LoadingRow
            # handler stays for rows WPF realises later as the user scrolls.
            $Script:Measured.TwoResults.RowsInspected | Should -BeGreaterThan 0
            $Script:Measured.TwoResults.RowHeadersSet | Should -Be $Script:Measured.TwoResults.RowsInspected
        }

        It 'numbers the rows across many stacked results, not just the first' {
            $Script:Measured.ManyResults.RowsInspected | Should -BeGreaterThan 0
            $Script:Measured.ManyResults.RowHeadersSet | Should -Be $Script:Measured.ManyResults.RowsInspected
        }

        It 'applies the ellipsis header template to every generated column' {
            # The second one-shot generation-time event, and a regression a reviewer caught after the
            # row-number half was fixed. AutoGeneratingColumn has already fired for every column by
            # the time these handlers attach, so the template is applied to the columns that exist -
            # otherwise the per-result grids lose the header trimming the single grid had.
            $Script:Measured.TwoResults.ColumnsSeen | Should -BeGreaterThan 0
            $Script:Measured.TwoResults.ColumnsTemplated | Should -Be $Script:Measured.TwoResults.ColumnsSeen
        }

        It 'templates the columns of every stacked result, not just the first' {
            $Script:Measured.ManyResults.ColumnsSeen | Should -BeGreaterThan 0
            $Script:Measured.ManyResults.ColumnsTemplated | Should -Be $Script:Measured.ManyResults.ColumnsSeen
        }

        It 'follows focus to the grid the user is working in' {
            # The behaviour the whole focused-result design rests on: Copy, Save Results As, Show
            # output and the context menu all act on this index. Proven by focusing a real grid and
            # reading what the tab session then believes.
            $Script:Measured.TwoResults.FocusFollowsGrid | Should -BeTrue
            $Script:Measured.TwoResults.FocusedIndexAfter | Should -Be 1
        }
    }

    Context 'AC 5 - two results share the pane equally' {

        It 'gives both grids the same height' {
            $Private:Heights = @($Script:Measured.TwoResults.GridHeights)
            @($Private:Heights).Count | Should -Be 2
            [math]::Abs($Private:Heights[0] - $Private:Heights[1]) | Should -BeLessThan 1
        }

        It 'gives each of them about half the available height' {
            # Half the viewport less the two headers, which are part of the item rather than the grid.
            #
            # The share is asserted against the RULE - Max(share, floor) - not against the share
            # alone, because those are different numbers whenever the pane is too short to give two
            # results five rows each. Asserting the bare share claimed a failure for a layout that was
            # correct: at a 700px window the viewport measured 161px, the share was 54.56 and the
            # floor 107.3, so the floor rightly won. The probe window is now tall enough that the
            # share wins here, which is what makes this a test of equal sharing at all - and the
            # assertion still holds if that ever stops being true.
            $Private:Heights = @($Script:Measured.TwoResults.GridHeights)
            $Private:Share = $Script:Measured.TwoResults.ExpectedShare
            $Private:Floor = $Script:Measured.TwoResults.Floor
            $Private:Expected = [math]::Max($Private:Share, $Private:Floor)

            [math]::Abs($Private:Heights[0] - $Private:Expected) | Should -BeLessThan 2
        }

        It 'is actually exercising the share rather than the floor' {
            # Guards the scenario itself. Without this, a window that shrank - or a floor that grew -
            # would quietly turn the test above into a second assertion about AC 6, and AC 5 would be
            # reported as covered while nothing tested it.
            $Script:Measured.TwoResults.ExpectedShare |
                Should -BeGreaterThan $Script:Measured.TwoResults.Floor
        }

        It 'does not let the taller result take more room than the shorter one' {
            # The failure this criterion exists to prevent: before the sizing pass, a 40-row result
            # arranged to 706px while a 3-row result took 75px, and the pane scrolled past the first.
            $Private:Heights = @($Script:Measured.TwoResults.GridHeights)
            $Private:Heights[1] | Should -BeLessThan 700
        }
    }

    Context 'AC 7 - a result taller than its share scrolls inside its own grid' {

        It 'leaves the 40-row grid scrollable rather than letting it grow' {
            # Its own scrollbar, not the pane's: the grid is shorter than its content, so the DataGrid's
            # internal ScrollViewer has somewhere to go.
            $Script:Measured.TwoResults.TallGridCanScrollInternally | Should -BeTrue
        }
    }

    Context 'AC 8 - one result fills the pane with no outer scrollbar' {

        It 'gives the single grid the whole viewport' {
            $Private:Single = $Script:Measured.OneResult
            [math]::Abs($Private:Single.GridHeight - $Private:Single.ExpectedHeight) | Should -BeLessThan 2
        }

        It 'shows no outer scrollbar' {
            # The visible difference a user would notice first, and the reason the sizing pass drives
            # every count including one: inside a StackPanel a stretched grid takes its NATURAL height,
            # so special-casing a single result in markup would quietly break this.
            $Script:Measured.OneResult.OuterScrollBarVisible | Should -BeFalse
        }
    }

    Context 'AC 6 - the five-row floor, and the pane scrolling because of it' {

        It 'keeps every result at the measured floor rather than shrinking further' {
            # Eight results in a pane that cannot give each of them five rows.
            $Private:Many = $Script:Measured.ManyResults
            foreach ($Private:Height in @($Private:Many.GridHeights)) {
                [math]::Abs($Private:Height - $Private:Many.Floor) | Should -BeLessThan 2
            }
        }

        It 'measures that floor as a header plus five data rows, not a hard-coded number' {
            # Row height is not fixed - Consolas with auto-generated columns - so the floor is measured.
            # These are the values this markup actually produces; they are asserted so that a styling
            # change which moves them is noticed rather than silently absorbed.
            $Private:Many = $Script:Measured.ManyResults
            $Private:Many.MeasuredRowHeight | Should -BeGreaterThan 10
            $Private:Many.MeasuredHeaderHeight | Should -BeGreaterThan 10
            [math]::Abs($Private:Many.Floor - ($Private:Many.MeasuredHeaderHeight + 5 * $Private:Many.MeasuredRowHeight)) | Should -BeLessThan 1
        }

        It 'makes the pane itself scroll once the floor wins' {
            # The whole point of the floor: the stack becomes taller than the viewport, so the outer
            # ScrollViewer has an extent to scroll through.
            $Private:Many = $Script:Measured.ManyResults
            $Private:Many.OuterScrollBarVisible | Should -BeTrue
            $Private:Many.ExtentHeight | Should -BeGreaterThan $Private:Many.ViewportHeight
        }
    }

    Context 'The grid resizes while the handle is being dragged' {
        # Issue #151 feedback, second round: the grids were resizable, but nothing moved until the
        # handle was released - so the user was dragging a grey bar with no idea what they were
        # choosing. ShowsPreview drew a preview adorner and applied the change only on DragCompleted.
        #
        # These assert on a real DragDelta raised on the real GridSplitter. Nothing else in the suite
        # could see this: the previous splitter coverage was the diagnostic script observing that a
        # GridSplitter exists somewhere in the visual tree, which stayed true the whole time the
        # behaviour was broken.

        It 'finds the splitter under the result it belongs to' {
            # Guards the three tests below, which are vacuous if no splitter was found to drag.
            $Script:Measured.TwoResults.ResizeProbe.SplitterFound | Should -BeTrue
        }

        It 'grows the grid as the handle moves, not when it is released' {
            # The fix itself. DragDelta carries the change since the LAST delta, so it is applied
            # incrementally - and DragCompleted no longer applies anything, or a 40px drag would move
            # the grid 80px.
            $Private:Resize = $Script:Measured.TwoResults.ResizeProbe
            $Private:Resize.HeightAfterDrag | Should -BeGreaterThan $Private:Resize.HeightBefore
            [math]::Abs($Private:Resize.HeightAfterDrag - ($Private:Resize.HeightBefore + 40)) | Should -BeLessThan 2
        }

        It 'stops at the measured floor rather than letting the grid collapse' {
            # A drag far past the top edge. Without the clamp the grid - and the splitter sitting at
            # the bottom of it - shrink to nothing, and there is no handle left to drag back.
            $Private:Resize = $Script:Measured.TwoResults.ResizeProbe
            $Private:Resize.Floor | Should -BeGreaterThan 10
            [math]::Abs($Private:Resize.HeightAfterClamp - $Private:Resize.Floor) | Should -BeLessThan 2
        }

        It 'marks the grid as user-sized so the next pane resize leaves it alone' {
            # The agreed behaviour: a dragged height sticks until the next execute. The mark is set on
            # the first delta rather than at the end of the drag, so the sizing pass is already
            # leaving the grid alone while the handle is still moving.
            $Script:Measured.TwoResults.ResizeProbe.UserSizedSet | Should -BeTrue
        }
    }
}

Describe "Moving focus between results clears the column-selection anchor" -Tag 'Sta' {
    # Issue #166, the silent half. A shift-click range-selects from the last column clicked, and that
    # anchor is module-scope state - so when focus moves to another result it has to be forgotten, or
    # the next shift-click ranges from a column in the grid the user has just left.
    #
    # Only measurable here. The clear was a bare `$Script:... = $null` inside the GotFocus handler,
    # which was then a .GetNewClosure() scriptblock: the assignment landed in the closure's own
    # detached scope and the variable the selection logic reads was never touched. Nothing threw,
    # nothing was logged, and no headless test could tell the two versions apart - the only evidence
    # is observing the variable after a real grid really takes focus.
    #
    # Register-QueryResultGridHandler.Tests.ps1 asserts the structure (that the handler calls the
    # function at all, and that no handler in that file is a closure). This asserts the consequence.

    BeforeEach {
        if ([string]::IsNullOrWhiteSpace($Script:WebView2Assembly)) {
            Set-ItResult -Inconclusive -Because "the bundled WebView2 assembly is not present; run ./build/build.ps1 -Task Dependencies first"
        }
        if ($null -eq $Script:Measured -or -not $Script:Measured.Ok) {
            Set-ItResult -Inconclusive -Because ("the STA layout probe did not report measurements: {0}" -f $Script:Measured.Error)
        }
    }

    It 'armed the anchor before moving focus, so the assertion below is not vacuous' {
        # Without this, an anchor that was never set would make "it is null afterwards" pass against
        # the broken code as well as the fixed code.
        $Script:Measured.TwoResults.AnchorProbe.SetBefore | Should -BeTrue
    }

    It 'actually moved focus to the other result' {
        # Separates "the handler did not run" from "the handler ran and did not clear", the same
        # distinction the focus probe above reports. An off-screen window that was never activated has
        # no keyboard focus to give.
        $Script:Measured.TwoResults.AnchorProbe.FocusCallReturned | Should -BeTrue
    }

    It 'leaves no anchor behind once another grid has focus' {
        # The fix: the write now goes through Clear-DataGridColumnSelectionAnchor, which owns the
        # variable in the scope that owns the state.
        $Script:Measured.TwoResults.AnchorProbe.ClearedAfter | Should -BeTrue
    }
}
