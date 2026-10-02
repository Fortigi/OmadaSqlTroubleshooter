# The STA half of QueryResultStackLayout.Sta.Tests.ps1 (issue #151).
#
# Runs in a `pwsh -STA` child process, loads the real MainFormTabContent.xaml, binds results into the
# Results pane, runs the sizing pass, and prints ONE JSON object of measurements for the parent to
# assert on. Nothing is asserted here: a probe that judged its own numbers would decide what "correct"
# means in the same place that produces them.
#
# Underscore-prefixed on purpose. The module's .psm1 skips _*.ps1 when it dot-sources, and - the part
# that actually matters - the name does not match psake's '*.Tests.ps1' filter, so this never gets
# collected as a test file in its own right.
#
# WPF needs STA and PowerShell 7 is MTA, which is why this is a separate process rather than a
# function: on an MTA thread ItemContainerGenerator never realises a container, so every measurement
# would silently come back as zero and the suite would pass while proving nothing.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$AssemblyPath
)

$ErrorActionPreference = "Stop"

function Write-ProbeFailure {
    param([string]$Message)
    @{ Ok = $false; Error = $Message } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

try {
    Add-Type -AssemblyName PresentationFramework

    # The Core assembly sits beside the Wpf one and is needed to instantiate the WebView2 element the
    # markup declares. Loaded first when present; a missing Core is reported rather than left to
    # surface as an opaque XAML type error.
    $CoreAssembly = Join-Path (Split-Path -Path $AssemblyPath -Parent) "Microsoft.Web.WebView2.Core.dll"
    if (Test-Path $CoreAssembly -PathType Leaf) { [void][Reflection.Assembly]::LoadFrom($CoreAssembly) }
    [void][Reflection.Assembly]::LoadFrom($AssemblyPath)

    $PrivatePath = Join-Path $RepositoryRoot "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath "Set-TabQueryResult.ps1")
    . (Join-Path $PrivatePath "Update-QueryResultStackLayout.ps1")
    # Registration is measured too, because nothing else can measure it. Its handlers close over the
    # grid's index with .GetNewClosure(), and whether that capture actually works is invisible to a
    # parse and to every headless test - the only proof is focusing a real grid and seeing the focused
    # index follow.
    . (Join-Path $PrivatePath "Register-QueryResultGridHandler.ps1")

    # The two collaborators the functions above reach for. Silent, because this process prints JSON and
    # nothing else - a stray log line would make the output unparseable.
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { }
    }
    function Invoke-SanitizeJsonKeys {
        param([Parameter(ValueFromPipeline = $true)]$InputObject)
        process { $InputObject }
    }

    $XamlPath = Join-Path $RepositoryRoot "src\Lib\ui\MainFormTabContent.xaml"
    $Stream = [System.IO.File]::OpenRead($XamlPath)
    try { $Control = [System.Windows.Markup.XamlReader]::Load($Stream) }
    finally { $Stream.Dispose() }

    $ItemsControl = $Control.FindName("ItemsControlQueryResults")
    $ScrollViewer = $Control.FindName("ScrollViewerQueryResults")

    if ($null -eq $ItemsControl -or $null -eq $ScrollViewer) {
        Write-ProbeFailure ("the stack container was not found by name (ItemsControl: {0}, ScrollViewer: {1})" -f ($null -ne $ItemsControl), ($null -ne $ScrollViewer))
    }

    # The tab session the production functions expect. Elements points at the real controls, so the
    # sizing pass measures the markup rather than a stand-in.
    $Session = [pscustomobject]@{
        Id                      = "sta-probe"
        Elements                = @{
            ItemsControlQueryResults = $ItemsControl
            ScrollViewerQueryResults = $ScrollViewer
        }
        QueryResults            = $null
        FocusedQueryResultIndex = 0
    }
    function Get-ActiveTabSession { return $Session }

    # Off-screen rather than hidden: the containers must be realised for anything to be measurable, and
    # a Window that is never shown realises nothing. Positioned far off the desktop so the run does not
    # flash a window in front of whoever is at the machine.
    $Window = New-Object System.Windows.Window
    $Window.Left = -10000
    $Window.Top = -10000
    $Window.Width = 1200
    # Deliberately tall. The tab content stacks the connection fields, the query editor and the output
    # pane, so the Results pane gets only what is left: in a 700px window its viewport measured 161px,
    # which is below two results' five-row floor (2 x 107.3) - so the floor won and the equal-share
    # criterion was never actually exercised. At this height the share wins for two results, which is
    # the only way AC 5 is tested rather than merely asserted.
    $Window.Height = 1400
    $Window.ShowInTaskbar = $false
    $Window.Content = $Control
    $Window.Show()
    $Window.UpdateLayout()

    function New-ProbeOutcome {
        param([int]$Ordinal, [int]$RowCount)
        $Rows = @()
        if ($RowCount -gt 0) {
            $Rows = @(1..$RowCount | ForEach-Object { [pscustomobject]@{ Name = "row$_"; Id = $_ } })
        }
        return @{
            Ordinal     = $Ordinal
            Text        = "SELECT $Ordinal"
            QueryResult = [pscustomobject]@{ d = [pscustomobject]@{ Records = $RowCount; Rows = $Rows } }
            ErrorRecord = $null
            FailedStep  = $null
        }
    }

    function Get-VisualDescendant {
        param($Parent, [type]$Type)
        if ($null -eq $Parent) { return $null }
        $Queue = [System.Collections.Generic.Queue[object]]::new()
        $Queue.Enqueue($Parent)
        while ($Queue.Count -gt 0) {
            $Node = $Queue.Dequeue()
            $Count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Node)
            for ($i = 0; $i -lt $Count; $i++) {
                $Child = [System.Windows.Media.VisualTreeHelper]::GetChild($Node, $i)
                if ($Type.IsInstanceOfType($Child)) { return $Child }
                $Queue.Enqueue($Child)
            }
        }
        return $null
    }

    function Measure-Scenario {
        # Binds a set of results, runs the sizing pass, lets layout settle, and reports what the pane
        # actually came out as.
        param([object[]]$Outcome)

        [void](Set-TabQueryResult -TabSession $Session -StatementOutcome $Outcome)
        $Window.UpdateLayout()

        # The inputs are captured HERE - after the containers are realised but BEFORE the sizing pass
        # runs - because these are the values Update-QueryResultStackLayout itself reads. Measuring the
        # viewport afterwards instead compares the result against a number the pass never saw: sizing
        # changes the content height, which can bring the outer scrollbar in or out and move the
        # viewport. That mistake made this probe report a ~53px discrepancy for a layout that was
        # correct.
        $Grids = [System.Collections.Generic.List[object]]::new()
        $Containers = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $ItemsControl.Items.Count; $i++) {
            $Container = $ItemsControl.ItemContainerGenerator.ContainerFromIndex($i)
            if ($null -eq $Container) { continue }
            $Containers.Add($Container)
            $Grid = Get-VisualDescendant -Parent $Container -Type ([System.Windows.Controls.DataGrid])
            if ($null -ne $Grid) { $Grids.Add($Grid) }
        }

        $ViewportBeforeSizing = [double]$ScrollViewer.ViewportHeight
        # The per-item overhead the pass allows for: everything in the item that is not the grid - its
        # header and the item's own margin.
        $AllowanceBeforeSizing = 0.0
        if ($Containers.Count -gt 0 -and $Grids.Count -gt 0 -and $Containers[0].ActualHeight -gt 0) {
            $AllowanceBeforeSizing = [math]::Max(0.0, [double]$Containers[0].ActualHeight - [double]$Grids[0].ActualHeight)
        }

        # The containers do not exist on the pass that assigned ItemsSource, which is exactly why
        # production defers both of these through the dispatcher. Here the layout pass above has
        # already realised them, so the calls are direct - and in the same order the completion uses.
        Register-QueryResultGridHandler -TabSession $Session
        Update-QueryResultStackLayout -TabSession $Session
        $Window.UpdateLayout()

        $RowHeight = 0.0
        $HeaderHeight = 0.0
        $Measurable = @($Grids | Where-Object { $_.Items.Count -gt 0 } | Select-Object -First 1)
        if ($Measurable.Count -gt 0) {
            $RowContainer = $Measurable[0].ItemContainerGenerator.ContainerFromIndex(0)
            if ($null -ne $RowContainer) { $RowHeight = [double]$RowContainer.ActualHeight }
            $Presenter = Get-VisualDescendant -Parent $Measurable[0] -Type ([System.Windows.Controls.Primitives.DataGridColumnHeadersPresenter])
            if ($null -ne $Presenter) { $HeaderHeight = [double]$Presenter.ActualHeight }
        }

        $TallGridScrolls = $false
        if ($Grids.Count -gt 0) {
            $Tall = $Grids[$Grids.Count - 1]
            $Inner = Get-VisualDescendant -Parent $Tall -Type ([System.Windows.Controls.ScrollViewer])
            if ($null -ne $Inner) { $TallGridScrolls = $Inner.ExtentHeight -gt ($Inner.ViewportHeight + 1) }
        }

        # Did the row-number handler actually take effect? LoadingRow sets each DataGridRow's Header
        # to its 1-based index. The handlers are attached AFTER the layout pass that realised the
        # containers - and that same pass is what loaded the rows - so the question is whether
        # LoadingRow had already fired for every row before the handler existed. A null header on a
        # realised row is that failure, observed rather than reasoned about.
        $RowHeadersSet = 0
        $RowsInspected = 0
        foreach ($InspectGrid in $Grids) {
            $InspectGrid.UpdateLayout()
            for ($r = 0; $r -lt [math]::Min(3, $InspectGrid.Items.Count); $r++) {
                $RowContainerToCheck = $InspectGrid.ItemContainerGenerator.ContainerFromIndex($r)
                if ($null -eq $RowContainerToCheck) { continue }
                $RowsInspected++
                if (![string]::IsNullOrWhiteSpace([string]$RowContainerToCheck.Header)) { $RowHeadersSet++ }
            }
        }

        # The column header template, the other one-shot generation-time event. AutoGeneratingColumn
        # has already fired for every column by the time the handlers attach, so the template has to
        # be applied to the existing columns - measured here rather than assumed.
        $ColumnsSeen = 0
        $ColumnsTemplated = 0
        foreach ($TemplateGrid in $Grids) {
            foreach ($GridColumn in @($TemplateGrid.Columns)) {
                $ColumnsSeen++
                if ($null -ne $GridColumn.HeaderTemplate) { $ColumnsTemplated++ }
            }
        }

        # Every grid wired exactly once. Tag is the registration marker, and it carries the grid's
        # index - so a Tag that is null means the handlers never attached, and a wrong one means the
        # closure captured the loop variable instead of its own iteration.
        # Tag is a hashtable carrying the grid's index and its user-sized flag, not a bare int.
        $RegisteredCount = @($Grids | Where-Object { $_.Tag -is [hashtable] }).Count
        $TagsMatchPosition = $true
        for ($t = 0; $t -lt $Grids.Count; $t++) {
            if (-not ($Grids[$t].Tag -is [hashtable]) -or [int]$Grids[$t].Tag.Index -ne $t) { $TagsMatchPosition = $false }
        }

        # The closure test proper: focus the LAST grid and see whether the session's focused index
        # follows it. With a broken capture every handler reports the same index and this stays at 0
        # for a multi-result run.
        $FocusFollowsGrid = $false
        $FocusedIndexAfter = -1
        $FocusCallReturned = $false
        $KeyboardFocusWithin = $false
        if ($Grids.Count -gt 1) {
            $Session.FocusedQueryResultIndex = 0

            # Activated first. An off-screen window that was shown but never activated has no keyboard
            # focus to give, so Focus() returns false and GotFocus never fires - which would look
            # exactly like a broken closure capture. Reporting the call's own result and
            # IsKeyboardFocusWithin is what separates "the handler did not run" from "the handler ran
            # with the wrong index".
            $Window.Activate()
            $FocusCallReturned = [bool]$Grids[$Grids.Count - 1].Focus()
            $Window.UpdateLayout()
            $KeyboardFocusWithin = [bool]$Grids[$Grids.Count - 1].IsKeyboardFocusWithin
            $FocusedIndexAfter = [int]$Session.FocusedQueryResultIndex
            $FocusFollowsGrid = ($FocusedIndexAfter -eq ($Grids.Count - 1))
        }

        return @{
            Count                      = $Grids.Count
            GridHeights                = @($Grids | ForEach-Object { [math]::Round([double]$_.ActualHeight, 2) })
            MeasuredRowHeight          = [math]::Round($RowHeight, 2)
            MeasuredHeaderHeight       = [math]::Round($HeaderHeight, 2)
            Floor                      = [math]::Round($HeaderHeight + 5 * $RowHeight, 2)
            ViewportHeight             = [math]::Round([double]$ScrollViewer.ViewportHeight, 2)
            ExtentHeight               = [math]::Round([double]$ScrollViewer.ExtentHeight, 2)
            OuterScrollBarVisible      = ($ScrollViewer.ComputedVerticalScrollBarVisibility -eq [System.Windows.Visibility]::Visible)
            # Both derived from the PRE-sizing viewport and allowance, because those are the inputs
            # Update-QueryResultStackLayout actually read. Recomputing them from the post-sizing
            # viewport compares the outcome against a number the pass never saw - sizing changes the
            # content height, which can bring the outer scrollbar in or out and move the viewport.
            ExpectedShare              = [math]::Round(($ViewportBeforeSizing - ($AllowanceBeforeSizing * $Grids.Count)) / [math]::Max(1, $Grids.Count), 2)
            ExpectedHeight             = [math]::Round($ViewportBeforeSizing - $AllowanceBeforeSizing, 2)
            ViewportBeforeSizing       = [math]::Round($ViewportBeforeSizing, 2)
            EveryGridHasContextMenu    = ($Grids.Count -gt 0 -and @($Grids | Where-Object { $null -eq $_.ContextMenu }).Count -eq 0)
            TallGridCanScrollInternally = $TallGridScrolls
            RegisteredCount            = $RegisteredCount
            TagsMatchPosition          = $TagsMatchPosition
            # Row numbering: LoadingRow sets each row's Header to its 1-based index. Measured because
            # the handlers attach AFTER the layout pass that realised the containers - and that same
            # pass loaded the rows - so the open question is whether LoadingRow had already fired.
            RowsInspected              = $RowsInspected
            RowHeadersSet              = $RowHeadersSet
            ColumnsSeen                = $ColumnsSeen
            ColumnsTemplated           = $ColumnsTemplated
            FocusFollowsGrid           = $FocusFollowsGrid
            FocusedIndexAfter          = $FocusedIndexAfter
            FocusCallReturned          = $FocusCallReturned
            KeyboardFocusWithin        = $KeyboardFocusWithin
        }
    }

    # Two results of very different sizes: the case that exposed the natural-height problem, where a
    # 40-row grid arranged to 706px against a 3-row grid's 75px.
    $TwoResults = Measure-Scenario -Outcome @((New-ProbeOutcome -Ordinal 1 -RowCount 3), (New-ProbeOutcome -Ordinal 2 -RowCount 40))

    # Eight results, so the equal share drops below five rows and the floor has to take over.
    $ManyResults = Measure-Scenario -Outcome @(1..8 | ForEach-Object { New-ProbeOutcome -Ordinal $_ -RowCount 20 })

    # One result, last: the case that must look exactly as it did before this issue.
    $OneScenario = Measure-Scenario -Outcome @((New-ProbeOutcome -Ordinal 1 -RowCount 3))
    $OneResult = @{
        GridHeight            = @($OneScenario.GridHeights)[0]
        ExpectedHeight        = $OneScenario.ExpectedHeight
        OuterScrollBarVisible = $OneScenario.OuterScrollBarVisible
        ViewportHeight        = $OneScenario.ViewportHeight
        ExtentHeight          = $OneScenario.ExtentHeight
    }

    $Window.Close()

    @{
        Ok                = $true
        ControlLoaded     = $true
        FoundItemsControl = $true
        FoundScrollViewer = $true
        TwoResults        = $TwoResults
        ManyResults       = $ManyResults
        OneResult         = $OneResult
    } | ConvertTo-Json -Depth 6 -Compress
}
catch {
    Write-ProbeFailure ("{0}{1}" -f $_.Exception.Message, $(if ($null -ne $_.Exception.InnerException) { " | INNER: " + $_.Exception.InnerException.Message } else { "" }))
}
