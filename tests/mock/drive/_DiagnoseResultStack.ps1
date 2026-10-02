#Requires -Version 7.0
<#
.SYNOPSIS
Unattended drive script: measures why the Results pane binds nothing in the live app (issue #151).

.DESCRIPTION
Dot-sourced by MockAppEntry.ps1 (via OMADASQL_MOCK_DRIVE) on the app's dispatcher thread, inside the
module session, after the replay transport shim is installed. Modelled on Verify-MockApp.ps1, which is
the working example of this contract.

Four candidate causes, distinguished by MEASURING rather than reasoning:

  1. Set-TabQueryResult never ran               -> SetTabQueryResultCalls is 0
  2. it ran but bailed before binding           -> calls > 0, TabQueryResultsCount 0, CallDetail says
                                                   what the pipeline handed it
  3. it bound to a different session's Elements -> TabQueryResultsCount > 0 but ItemsSourceCount 0
  4. it bound fine and the harness misreads     -> ItemsSourceCount > 0

Nothing is asserted here. A probe that judged its own numbers would decide what "correct" means in the
same place that produces them.

Do NOT combine with -AutoConnect: the no-dialog Write-LogOutput override below has to exist before
anything can log, and connecting first risks a modal MessageBox deadlocking the dispatcher.
#>

# --- 1. Neutralize blocking dialogs BEFORE anything can log ----------------------------------------
$script:DriveLogMessages = [System.Collections.Generic.List[object]]::new()

function script:Write-LogOutput {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [string]$Message,
        $ErrorObject,
        [ValidateSet("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2")]
        [string]$LogType = "INFO",
        [switch]$SkipDialog
    )
    process {
        $script:DriveLogMessages.Add([PSCustomObject]@{ LogType = $LogType; Message = $Message })
    }
}

function script:Wait-DriveIdle {
    param([int]$Milliseconds = 750)

    $Deadline = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    while ([DateTime]::UtcNow -lt $Deadline) {
        # Background priority, which is what the execute completion defers its sizing and handler
        # registration to.
        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
        Start-Sleep -Milliseconds 50
    }
}

$Report = [ordered]@{}

try {
    # --- 2. Watch Set-TabQueryResult without changing what it does ---------------------------------
    $script:ProbeCalls = [System.Collections.Generic.List[object]]::new()
    $script:RealSetTabQueryResult = ${function:Set-TabQueryResult}

    function script:Set-TabQueryResult {
        param($TabSession, $StatementOutcome)

        $Private:Live = @($StatementOutcome | Where-Object { $null -ne $_ })
        $script:ProbeCalls.Add([PSCustomObject]@{
                OutcomeCount = $Private:Live.Count
                SessionId    = [string]$TabSession.Id
                HasElements  = ($null -ne $TabSession.Elements)
                HasItemsCtl  = ($null -ne $TabSession.Elements.ItemsControlQueryResults)
                Shapes       = @($Private:Live | ForEach-Object {
                        "ord={0} err={1} rows={2} records={3}" -f $_.Ordinal, ($null -ne $_.ErrorRecord), @($_.QueryResult.d.Rows).Count, $_.QueryResult.d.Records
                    })
            })

        return (& $script:RealSetTabQueryResult -TabSession $TabSession -StatementOutcome $StatementOutcome)
    }

    # --- 3. Drive the real UI ----------------------------------------------------------------------
    $Elements = $Script:MainForm.Elements

    $Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    Wait-DriveIdle -Milliseconds 6000

    $Report.Connected = [bool]$Script:ConnectionStatus
    $Report.QueryItems = @($Elements.ComboBoxSelectQuery.Items).Count

    # Select the fixture query, the way Verify-MockApp does: pick the dropdown entry and let the
    # SelectionChanged handler load it.
    $Private:Item = @($Elements.ComboBoxSelectQuery.Items) | Select-Object -First 1
    if ($null -ne $Private:Item) {
        $Elements.ComboBoxSelectQuery.SelectedItem = $Private:Item
        Wait-DriveIdle -Milliseconds 3000
    }
    $Report.SelectedQuery = [string]$Elements.ComboBoxSelectQuery.SelectedItem.Content

    # A MULTI-STATEMENT run, which is the whole point of issue #151 and the only way the Messages
    # breakdown and the export filename's statement token can be seen in the running application. The
    # mock's stored query is a single statement, so the editor text is replaced with two.
    #
    # Pushed through RunTimeData rather than the Monaco editor: the editor read is asynchronous and
    # the execute path takes QueryText from here, which is what the splitter and the pipeline see.
    $Script:RunTimeData.QueryText = "SELECT TOP 3 Id FROM dbo.tblDataObject;" + [Environment]::NewLine + "SELECT TOP 4 Id FROM dbo.tblDataObject;"

    $Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    Wait-DriveIdle -Milliseconds 12000

    # --- 4. Measure --------------------------------------------------------------------------------
    $Tab = Get-ActiveTabSession

    $Report.SetTabQueryResultCalls = @($script:ProbeCalls).Count
    $Report.CallDetail = @($script:ProbeCalls | ForEach-Object {
            "outcomes={0} session={1} elements={2} itemsControl={3} [{4}]" -f $_.OutcomeCount, $_.SessionId, $_.HasElements, $_.HasItemsCtl, ($_.Shapes -join "; ")
        })

    $Report.TabQueryResultsCount = @($Tab.QueryResults).Count
    $Report.FocusedIndex = [string]$Tab.FocusedQueryResultIndex
    $Report.ItemsControlResolved = ($null -ne $Elements.ItemsControlQueryResults)
    $Report.ScrollViewerResolved = ($null -ne $Elements.ScrollViewerQueryResults)
    $Report.ItemsSourceNull = ($null -eq $Elements.ItemsControlQueryResults.ItemsSource)
    $Report.ItemsSourceCount = @($Elements.ItemsControlQueryResults.ItemsSource | Where-Object { $null -ne $_ }).Count
    $Report.SameElementsObject = [object]::ReferenceEquals($Elements, $Tab.Elements)
    $Report.FocusedGridNull = ($null -eq (Get-FocusedQueryResultGrid))

    $Report.RunTimeQueryRecords = [string]$Script:RunTimeData.QueryResult.d.Records
    $Report.LastRowsRead = [string]$Script:RunTimeData.LastRowsRead
    $Report.StatusBarRows = [string]$Elements.TextBlockStatusBarRows.Text

    # --- 5. The feedback items, checked in the RUNNING application --------------------------------
    # Unit tests and the STA probe cover these in isolation; this is the only place that sees them
    # happen in the real app, which is what found the two silent binding bugs in the first place.

    # Row numbers: every realised row's Header should carry its 1-based index.
    $Private:FocusedGrid = Get-FocusedQueryResultGrid
    $Private:RowsSeen = 0
    $Private:RowsNumbered = 0
    if ($null -ne $Private:FocusedGrid) {
        $Private:FocusedGrid.UpdateLayout()
        for ($Private:R = 0; $Private:R -lt [math]::Min(5, $Private:FocusedGrid.Items.Count); $Private:R++) {
            $Private:RowContainer = $Private:FocusedGrid.ItemContainerGenerator.ContainerFromIndex($Private:R)
            if ($null -eq $Private:RowContainer) { continue }
            $Private:RowsSeen++
            if (![string]::IsNullOrWhiteSpace([string]$Private:RowContainer.Header)) { $Private:RowsNumbered++ }
        }
    }
    $Report.RowsSeen = $Private:RowsSeen
    $Report.RowsNumbered = $Private:RowsNumbered

    # The Messages pane, verbatim - so the per-statement breakdown can be read rather than inferred.
    $Report.MessagesPaneLines = @($Tab.QueryMessages)

    # Is the resize handle actually in the realised tree, and did registration mark the grid?
    $Private:SplitterFound = $false
    $Private:TagShape = "none"
    if ($null -ne $Private:FocusedGrid) {
        if ($Private:FocusedGrid.Tag -is [hashtable]) {
            $Private:TagShape = "hashtable UserSized={0}" -f $Private:FocusedGrid.Tag.UserSized
        }
        elseif ($null -ne $Private:FocusedGrid.Tag) {
            $Private:TagShape = $Private:FocusedGrid.Tag.GetType().Name
        }

        $Private:Container = $Elements.ItemsControlQueryResults.ItemContainerGenerator.ContainerFromIndex(0)
        $Private:Queue = [System.Collections.Generic.Queue[object]]::new()
        if ($null -ne $Private:Container) { $Private:Queue.Enqueue($Private:Container) }
        while ($Private:Queue.Count -gt 0 -and -not $Private:SplitterFound) {
            $Private:Node = $Private:Queue.Dequeue()
            $Private:Count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Private:Node)
            for ($Private:I = 0; $Private:I -lt $Private:Count; $Private:I++) {
                $Private:Child = [System.Windows.Media.VisualTreeHelper]::GetChild($Private:Node, $Private:I)
                if ($Private:Child -is [System.Windows.Controls.GridSplitter]) { $Private:SplitterFound = $true; break }
                $Private:Queue.Enqueue($Private:Child)
            }
        }
    }
    $Report.SplitterInTree = $Private:SplitterFound
    $Report.FocusedGridTag = $Private:TagShape

    # The app's own account of the run - the execute path logs statement counts and row counts.
    $Report.RelevantLog = @($script:DriveLogMessages |
            Where-Object { $_.Message -match 'statement|record\(s\)|did not return|Sized|result grid' } |
            ForEach-Object { "[{0}] {1}" -f $_.LogType, $_.Message } |
            Select-Object -First 25)
    $Report.ErrorLog = @($script:DriveLogMessages |
            Where-Object { $_.LogType -in @("ERROR", "FATAL") } |
            ForEach-Object { "[{0}] {1}" -f $_.LogType, $_.Message } |
            Select-Object -First 15)
}
catch {
    $Report.ProbeError = $_.Exception.Message
    $Report.ProbeErrorAt = [string]$_.ScriptStackTrace
}

$Json = [PSCustomObject]$Report | ConvertTo-Json -Depth 6
if (![string]::IsNullOrWhiteSpace($env:OMADASQL_MOCK_RESULTS)) {
    $Json | Set-Content -Path $env:OMADASQL_MOCK_RESULTS -Encoding utf8NoBOM
}
$Json | Write-Host

# --- 5. Close, so the unattended run ends rather than timing out -----------------------------------
$Script:MainForm.Definition.Dispatcher.Invoke([System.Action] { $Script:MainForm.Definition.Close() }, [System.Windows.Threading.DispatcherPriority]::Normal)
