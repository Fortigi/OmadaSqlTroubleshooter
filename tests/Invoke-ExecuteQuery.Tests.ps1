#Requires -Version 7.0
# Tests for the two halves issue #40 split out of Invoke-ExecuteQuery's completion block:
# Reset-ExecuteQueryUiState (the teardown) and Complete-ExecuteQueryResult (everything that happens
# once a result is in hand). Both are UI-thread-only and are now reached from three places - the
# inline path, the background completion, and the failure paths - so they are worth asserting
# directly rather than only through the E2E suite, which does not run in CI.

BeforeAll {
    # Complete-ExecuteQueryResult builds a real System.Windows.Controls.ComboBoxItem when a renamed
    # query has to be re-selected. That type lives in PresentationFramework, which a headless CI pwsh
    # does not load on its own - without this the call throws inside the function's own catch and the
    # selection is silently never set, so the test passes locally (where WPF is already loaded) and
    # fails in CI. Mirrors the Add-Type in Update-QueryList.Tests.ps1, which carries the same note.
    Add-Type -AssemblyName PresentationFramework

    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogResultShape.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-TextBlockText.ps1")
    # Reset-ExecuteQueryUiState now also flips the Execute/Cancel button (issue #40 / C1-4). The real
    # chain is dot-sourced rather than stubbed: a missing collaborator would throw inside this
    # function's own catch and silently skip the rest of the teardown, which is exactly the failure
    # mode these tests exist to catch.
    . (Join-Path $PrivatePath -ChildPath "Set-ButtonText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ActiveExecuteQueryRequest.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-ExecuteQueryButtonState.ps1")
    # Both are dot-sourced rather than stubbed, and for the same reason as the chain above: the
    # containment these two provide IS the behaviour under test in the cascade suite, so a stub would
    # assert nothing.
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ExecutePipelineLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-ExecuteQuery.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Get-ActiveTabSession { return [pscustomobject]@{ Id = "tab-A" } }

    # --- Collaborators of the UI-thread re-drive ---------------------------------------------------
    $script:DisableReasons = [System.Collections.Generic.List[string]]::new()
    function Disable-OmadaBackgroundRequest {
        param([string]$Reason)
        $script:DisableReasons.Add([string]$Reason)
    }

    function Build-OmadaRequestParameter { return @{ SessionKey = "pool" } }

    # Records what the inline retry was asked to run, and answers with whatever the test set up.
    $script:InlinePipelineRuns = [System.Collections.Generic.List[object]]::new()
    function Invoke-OmadaExecutePipeline {
        param([hashtable]$Context)
        $script:InlinePipelineRuns.Add($Context)
        return $script:InlinePipelineOutcome
    }

    function script:New-PipelineOutcome {
        param(
            $QueryResult = $null,
            $ErrorRecord = $null,
            [int]$CompletedSteps = 1,
            $SaveResult = ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }),
            $Log = @()
        )
        return @{
            Log            = $Log
            SaveResult     = $SaveResult
            SaveSkipped    = $false
            TempQueryDoId  = $null
            QueryResult    = $QueryResult
            ErrorRecord    = $ErrorRecord
            FailedStep     = $(if ($null -ne $ErrorRecord) { "GetQueryObject" } else { $null })
            Steps          = @(@{ Name = "GetQueryObject"; Method = "GET"; Uri = "https://tenant/x" })
            CompletedSteps = $CompletedSteps
        }
    }

    function script:New-TestErrorRecord {
        param([string]$Message = "no session")
        return [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message), "TestFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
    }

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    $script:RemovedQueryObjects = [System.Collections.Generic.List[object]]::new()
    function Remove-SqlQueryObject {
        param($DoId)
        $script:RemovedQueryObjects.Add($DoId)
    }

    $script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
    function Set-ConfigProperty {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$Property
        )
        process { $script:ConfigWrites.Add([pscustomobject]@{ Property = $Property; Value = $InputObject }) }
    }

    $script:QueryListRefreshes = 0
    function Update-QueryList {
        param([switch]$ForceRefresh)
        $script:QueryListRefreshes++
    }

    function Invoke-SanitizeJsonKeys {
        param([Parameter(ValueFromPipeline = $true)]$InputObject)
        process { $InputObject }
    }

    function script:New-PopupStub {
        $Popup = [pscustomobject]@{ Closed = $false }
        $Popup | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed = $true }
        return $Popup
    }

    function script:Initialize-ExecuteQueryTestState {
        $script:RemovedQueryObjects.Clear()
        $script:ConfigWrites.Clear()
        $script:QueryListRefreshes = 0
        $script:DisableReasons.Clear()
        $script:InlinePipelineRuns.Clear()
        $script:InlinePipelineOutcome = New-PipelineOutcome -QueryResult (New-ResultResponse -RowCount 2)

        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        # The tab is connected unless a test says otherwise: the teardown only re-enables the query
        # controls for a connected tab.
        $Script:ConnectionStatus = $true
        # No request outstanding, so the button state resolves to "Execute".
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $Script:PopupWindowExecuteQuery = New-PopupStub
        $Script:AppConfig = [PSCustomObject]@{
            CurrentSqlQuery = [PSCustomObject]@{ DoId = 100; FullName = "TestQuery - 100" }
        }
        $Script:RunTimeData = [PSCustomObject]@{
            QueryResult     = $null
            StopWatch       = [System.Diagnostics.Stopwatch]::StartNew()
            CurrentSqlQuery = [PSCustomObject]@{ DisplayName = "TestQuery" }
        }
        $Script:MainForm = @{
            Elements = @{
                ButtonSaveQuery             = [PSCustomObject]@{ IsEnabled = $false }
                ButtonExecuteQuery          = [PSCustomObject]@{ IsEnabled = $false; ToolTip = "Execute" }
                ButtonExecuteQueryText      = [PSCustomObject]@{ Name = "ButtonExecuteQueryText"; Text = "_Cancel" }
                ButtonExecuteQueryImage     = [PSCustomObject]@{ Name = "ButtonExecuteQueryImage"; Text = [char]0xE711 }
                ButtonShowOutput            = [PSCustomObject]@{ IsEnabled = $false }
                ButtonSaveOutputFile        = [PSCustomObject]@{ IsEnabled = $false }
                DataGridQueryResult         = [PSCustomObject]@{ ItemsSource = "previous"; AutoGenerateColumns = $false }
                TextBlockStatusBarRows      = [PSCustomObject]@{ Name = "TextBlockStatusBarRows"; Text = "-" }
                TextBlockStatusBarQueryTime = [PSCustomObject]@{ Name = "TextBlockStatusBarQueryTime"; Text = "-" }
                ComboBoxSelectQuery         = [PSCustomObject]@{ Items = [System.Collections.ArrayList]::new(); SelectedItem = $null }
            }
        }
    }

    function script:New-ResultResponse {
        param([int]$RowCount = 2)
        $Rows = @(1..$RowCount | ForEach-Object { [pscustomobject]@{ Col1 = "v$_" } })
        if ($RowCount -eq 0) { $Rows = @() }
        return [pscustomobject]@{ d = [pscustomobject]@{ Records = $RowCount; Rows = $Rows } }
    }
}

Describe "Reset-ExecuteQueryUiState" {
    BeforeEach { Initialize-ExecuteQueryTestState }

    It "re-enables the buttons the execute click disabled" {
        Reset-ExecuteQueryUiState

        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
    }

    It "does not re-enable the query controls for a tab that is no longer connected" {
        # A query can outlive the connection it was issued on: the user can disconnect, or a 401 can
        # tear the tab down through Set-SqlConnectionState, while the request is still in flight -
        # and the completion runs afterwards regardless. Re-enabling unconditionally would hand a
        # disconnected tab a live Execute and Save button, which is issue #65's "in-between tab
        # state" arrived at from a new direction.
        $Script:ConnectionStatus = $false

        Reset-ExecuteQueryUiState

        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeFalse
    }

    It "still returns the button to Execute on a disconnected tab" {
        # The label has to be corrected either way: a tab must never be left showing Cancel with
        # nothing to cancel, whether or not it is still connected.
        $Script:ConnectionStatus = $false

        Reset-ExecuteQueryUiState

        $Script:MainForm.Elements.ButtonExecuteQueryText.Text | Should -Be "_Execute"
    }

    It "puts the Execute/Cancel button back to Execute" {
        # Every terminal path goes through here - success, failure and cancellation alike - so this
        # is the single place that guarantees a tab cannot be left showing Cancel with nothing to
        # cancel.
        Reset-ExecuteQueryUiState

        $Script:MainForm.Elements.ButtonExecuteQueryText.Text | Should -Be "_Execute"
    }

    It "closes the 'Executing Query...' popup and forgets it" {
        $Popup = $Script:PopupWindowExecuteQuery

        Reset-ExecuteQueryUiState

        $Popup.Closed | Should -BeTrue
        # Nulled as well as closed: a stale reference would be Close()d a second time by the next
        # execute's teardown.
        $Script:PopupWindowExecuteQuery | Should -BeNullOrEmpty
    }

    It "stops the stopwatch and writes its value to the status bar" {
        Reset-ExecuteQueryUiState

        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
        $Script:MainForm.Elements.TextBlockStatusBarQueryTime.Text | Should -Match '^\d{2}:\d{2}:\d{2}'
    }

    It "can stop the stopwatch without writing a time that would mean nothing" {
        Reset-ExecuteQueryUiState -SkipStatusBarTime

        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
        $Script:MainForm.Elements.TextBlockStatusBarQueryTime.Text | Should -Be "-"
    }

    It "leaves the results grid untouched" {
        # A failed or abandoned execute must not blank a perfectly good previous result.
        Reset-ExecuteQueryUiState

        $Script:MainForm.Elements.DataGridQueryResult.ItemsSource | Should -Be "previous"
    }

    It "does not throw when there is no popup and no stopwatch" {
        $Script:PopupWindowExecuteQuery = $null
        $Script:RunTimeData.StopWatch = $null

        { Reset-ExecuteQueryUiState } | Should -Not -Throw
    }
}

Describe "Complete-ExecuteQueryResult" {
    BeforeEach { Initialize-ExecuteQueryTestState }

    It "binds the rows and reports the record count" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse -RowCount 2) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        @($Script:MainForm.Elements.DataGridQueryResult.ItemsSource).Count | Should -Be 2
        $Script:MainForm.Elements.TextBlockStatusBarRows.Text | Should -Be "2 rows"
        $Script:MainForm.Elements.ButtonShowOutput.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled | Should -BeTrue
    }

    It "publishes the result so the export and grid-view features can read it" {
        $Response = New-ResultResponse -RowCount 2

        Complete-ExecuteQueryResult -QueryResult $Response -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        $Script:RunTimeData.QueryResult | Should -Be $Response
    }

    It "treats a null result as no rows rather than binding a phantom one" {
        # A null result used to fall through to the binding branch, where @($null.d.Rows) is a
        # one-element array containing $null: the grid showed a phantom row and the output buttons
        # were enabled for a result that does not exist. Null became far more reachable once a
        # request could fail or be abandoned in a worker.
        Complete-ExecuteQueryResult -QueryResult $null -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.DataGridQueryResult.ItemsSource | Should -BeNullOrEmpty
        $Script:MainForm.Elements.TextBlockStatusBarRows.Text | Should -Be "0 rows"
        $Script:MainForm.Elements.ButtonShowOutput.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled | Should -BeFalse
    }

    It "clears the grid and says '0 rows' for an empty result" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse -RowCount 0) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.DataGridQueryResult.ItemsSource | Should -BeNullOrEmpty
        $Script:MainForm.Elements.TextBlockStatusBarRows.Text | Should -Be "0 rows"
    }

    It "deletes the temporary selection object" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId "TMP-42"

        $script:RemovedQueryObjects | Should -Contain "TMP-42"
    }

    It "deletes the temporary object even when the request failed" {
        # A result that never arrived still leaves an object behind on the tenant.
        Complete-ExecuteQueryResult -QueryResult $null -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId "TMP-43"

        $script:RemovedQueryObjects | Should -Contain "TMP-43"
    }

    It "returns the UI to a usable state on every path" {
        Complete-ExecuteQueryResult -QueryResult $null -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeTrue
        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
    }

    It "selects the renamed query in the dropdown instead of clearing the selection" {
        # Regression guard. This block used to test a variable that had never been assigned, so its
        # body was unreachable and the line after it selected $null - executing a renamed query
        # silently emptied the query dropdown. Find-or-create, then select, as Save-Query does.
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "RenamedQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem | Should -Not -BeNullOrEmpty
        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem.Content | Should -Be "TestQuery - 100"
    }

    It "reuses an existing dropdown entry rather than adding a duplicate" {
        $Existing = [pscustomobject]@{ Content = "TestQuery - 100" }
        [void]$Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($Existing)

        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "RenamedQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Count | Should -Be 1
        [object]::ReferenceEquals($Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem, $Existing) | Should -BeTrue
    }

    It "refreshes the query list only when the display name actually changed" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null
        $script:QueryListRefreshes | Should -Be 0

        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "RenamedQuery" }) -TempQueryDoId $null
        $script:QueryListRefreshes | Should -Be 1
    }

    It "uses the SaveResult it was handed rather than re-reading module state" {
        # The correctness argument for passing it on the pending item: by the time a background
        # response lands, the frame that produced this value has long since returned, and the active
        # tab may be a different one.
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 777; DisplayName = "FromTheRequest" }) -TempQueryDoId $null

        $Written = @($script:ConfigWrites | Where-Object { $_.Property -eq "CurrentSqlQuery" })
        $Written.Count | Should -BeGreaterThan 0
        $Written.Value | Should -Contain 777
    }

    It "does not throw when the response is an ErrorRecord" {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("boom"), "OmadaFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        { Complete-ExecuteQueryResult -QueryResult $ErrorRecord -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null } | Should -Not -Throw
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
    }
}

Describe "Complete-ExecuteQueryPipeline falls back to the UI thread" {
    # The bug this suite exists for, found on a live tenant: every background request failed because
    # the worker's own OmadaWeb.PS could not establish a session, and the failure was reported through
    # the empty-result path - so every single query said "Query did not return any results!" and the
    # real error never reached the log at all.

    BeforeEach {
        Initialize-ExecuteQueryTestState
        $script:RetryContext = @{ BaseUrl = "https://tenant.omada.cloud"; QueryDoId = 100 }
    }

    It "re-runs the query on the UI thread when the worker returned nothing" {
        Complete-ExecuteQueryPipeline -Outcome $null -PipelineContext $script:RetryContext

        $script:InlinePipelineRuns.Count | Should -Be 1
        # And the user actually gets their result, rather than a warning about an empty one.
        @($Script:MainForm.Elements.DataGridQueryResult.ItemsSource).Count | Should -Be 2
    }

    It "re-runs the query on the UI thread when the worker returned only an error" {
        Complete-ExecuteQueryPipeline -Outcome (New-TestErrorRecord) -PipelineContext $script:RetryContext

        $script:InlinePipelineRuns.Count | Should -Be 1
        @($Script:MainForm.Elements.DataGridQueryResult.ItemsSource).Count | Should -Be 2
    }

    It "re-runs the query when the pipeline failed without reaching the tenant" {
        # CompletedSteps 0: the very first request failed, so no query ran, nothing was saved and no
        # temporary object exists. Retrying cannot repeat work the server already did.
        $Failed = New-PipelineOutcome -ErrorRecord (New-TestErrorRecord) -CompletedSteps 0

        Complete-ExecuteQueryPipeline -Outcome $Failed -PipelineContext $script:RetryContext

        $script:InlinePipelineRuns.Count | Should -Be 1
        @($Script:MainForm.Elements.DataGridQueryResult.ItemsSource).Count | Should -Be 2
    }

    It "does NOT re-run when a request had already reached the tenant" {
        # The other side of the gate, and the one that protects the user's data: if any step
        # succeeded, the failure is the tenant's answer. Re-running could execute the query twice.
        $Failed = New-PipelineOutcome -ErrorRecord (New-TestErrorRecord "SQL error") -CompletedSteps 2

        Complete-ExecuteQueryPipeline -Outcome $Failed -PipelineContext $script:RetryContext

        $script:InlinePipelineRuns.Count | Should -Be 0
    }

    It "disables background execution for the session when it falls back" {
        Complete-ExecuteQueryPipeline -Outcome (New-TestErrorRecord "no session") -PipelineContext $script:RetryContext

        $script:DisableReasons.Count | Should -Be 1
        $script:DisableReasons[0] | Should -Match "no session"
    }

    It "does not disable background execution for a genuine tenant failure" {
        $Failed = New-PipelineOutcome -ErrorRecord (New-TestErrorRecord "SQL error") -CompletedSteps 2

        Complete-ExecuteQueryPipeline -Outcome $Failed -PipelineContext $script:RetryContext

        $script:DisableReasons.Count | Should -Be 0
    }

    It "retries with a COPY of the context, leaving the caller's untouched" {
        # The retry adds the prepared transport splat. Mutating the caller's hashtable would leave a
        # stale Parameters key on a context that may be reused.
        Complete-ExecuteQueryPipeline -Outcome $null -PipelineContext $script:RetryContext

        $script:RetryContext.ContainsKey("Parameters") | Should -BeFalse
        $script:InlinePipelineRuns[0].ContainsKey("Parameters") | Should -BeTrue
    }

    It "reports the failure rather than doing nothing when there is no context to retry with" {
        Complete-ExecuteQueryPipeline -Outcome $null -PipelineContext $null

        $script:InlinePipelineRuns.Count | Should -Be 0
        # Still leaves the tab usable: the popup closed and the buttons back.
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
    }

    It "does not retry a second time when the inline run also fails" {
        # Guards against a fallback loop: the inline outcome goes through the same completion, and
        # must not send it round again.
        $script:InlinePipelineOutcome = New-PipelineOutcome -ErrorRecord (New-TestErrorRecord) -CompletedSteps 0

        Complete-ExecuteQueryPipeline -Outcome $null -PipelineContext $script:RetryContext

        $script:InlinePipelineRuns.Count | Should -Be 1
    }
}

Describe "Complete-ExecuteQueryPipeline does not retry a tab that was torn down" {
    # Resolve-OmadaRequestFailure disconnects the tab through Set-SqlConnectionState for the two
    # tenant-level failures (Unauthorized, OData endpoint missing) and then throws - and the
    # completion still runs, because the async wrapper invokes it in a finally. Those are the
    # tenant's answer, not a worker that could not do its job.

    BeforeEach {
        Initialize-ExecuteQueryTestState
        $script:RetryContext = @{ BaseUrl = "https://tenant.omada.cloud"; QueryDoId = 100 }
        $Script:ConnectionStatus = $false
    }

    It "does not re-run the query when the tab is no longer connected" {
        Complete-ExecuteQueryPipeline -Outcome (New-TestErrorRecord "Access denied") -PipelineContext $script:RetryContext

        $script:InlinePipelineRuns.Count | Should -Be 0
    }

    It "does not disable background execution over an expired session" {
        # The wrong conclusion to draw: a 401 says nothing about whether workers can authenticate,
        # and turning the feature off for the session because of one would be a permanent penalty
        # for a transient condition.
        Complete-ExecuteQueryPipeline -Outcome (New-TestErrorRecord "Access denied") -PipelineContext $script:RetryContext

        $script:DisableReasons.Count | Should -Be 0
    }

    It "still leaves the tab in a usable state" {
        Complete-ExecuteQueryPipeline -Outcome (New-TestErrorRecord "Access denied") -PipelineContext $script:RetryContext

        # Disconnected, so the query controls stay disabled - but the popup is closed, the stopwatch
        # stopped and the button reads Execute rather than Cancel.
        $Script:PopupWindowExecuteQuery | Should -BeNullOrEmpty
        $Script:MainForm.Elements.ButtonExecuteQueryText.Text | Should -Be "_Execute"
        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
    }
}

Describe "Complete-ExecuteQueryPipeline reports a tenant failure once" {
    # Found on a live tenant: one HTTP 500 produced FIVE stacked error dialogs and a log entry
    # containing four nested copies of itself. Write-LogOutput -LogType ERROR ends with Write-Error,
    # which under this application's $ErrorActionPreference = Stop is terminating - so reporting the
    # pipeline failure threw before the grid was bound, the function's own catch reported the throw
    # as a second error, which threw again, and so on out to the dispatcher.
    #
    # These tests only mean anything with a Write-LogOutput that throws on ERROR the way the real one
    # does; the suite's default stub is a no-op and would pass whatever the code did.

    BeforeEach {
        Initialize-ExecuteQueryTestState
        $script:ErrorLines = [System.Collections.Generic.List[string]]::new()
        $script:ReplayedLines = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogOutput {
            if ($LogType -eq "ERROR") {
                $script:ErrorLines.Add([string]$InputObject)
                Write-Error -Message ([string]$InputObject) -ErrorAction Stop
            }
            $script:ReplayedLines.Add([string]$InputObject)
        }
    }

    It "writes one ERROR, not a cascade of them" {
        $Failed = New-PipelineOutcome -ErrorRecord (New-TestErrorRecord "Response status code does not indicate success: 500 (Internal Server Error)") -CompletedSteps 2

        { Complete-ExecuteQueryPipeline -Outcome $Failed -PipelineContext @{ BaseUrl = "https://tenant.omada.cloud"; QueryDoId = 100 } } | Should -Not -Throw

        @($script:ErrorLines).Count | Should -Be 1
        $script:ErrorLines[0] | Should -Match "500"
    }

    It "still returns the UI to a usable state after the failure" {
        # The user-visible half of the same bug. The report threw before Complete-ExecuteQueryResult
        # ran, so the Execute button stayed disabled and the stopwatch kept running: the window was
        # left believing a query was still in flight.
        $Failed = New-PipelineOutcome -ErrorRecord (New-TestErrorRecord "500") -CompletedSteps 2

        Complete-ExecuteQueryPipeline -Outcome $Failed -PipelineContext @{ BaseUrl = "https://tenant.omada.cloud"; QueryDoId = 100 }

        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
    }

    It "replays what the worker recorded, so an execute is still traceable in the log" {
        # Moving the chain into a worker took the URLs, bodies and responses out of the log. They come
        # back through the outcome's Log, and they have to survive a FAILED run - that is precisely
        # when someone reads the log.
        $Failed = New-PipelineOutcome -ErrorRecord (New-TestErrorRecord "500") -CompletedSteps 2 -Log @(
            @{ Level = "DEBUG"; Text = "QueryUrl: https://tenant.omada.cloud/api/x" }
            @{ Level = "INFO"; Text = "Retrieve query output, please wait..." }
        )

        Complete-ExecuteQueryPipeline -Outcome $Failed -PipelineContext @{ BaseUrl = "https://tenant.omada.cloud"; QueryDoId = 100 }

        @($script:ReplayedLines) | Should -Contain "QueryUrl: https://tenant.omada.cloud/api/x"
        @($script:ReplayedLines) | Should -Contain "Retrieve query output, please wait..."
    }

    It "replays the worker's log on a successful run too" {
        $Succeeded = New-PipelineOutcome -QueryResult ([pscustomobject]@{ d = [pscustomobject]@{ Records = 2; Rows = @(1, 2) } }) -Log @(
            @{ Level = "DEBUG"; Text = "QueryUrl: https://tenant.omada.cloud/api/x" }
        )

        Complete-ExecuteQueryPipeline -Outcome $Succeeded -PipelineContext @{ BaseUrl = "https://tenant.omada.cloud"; QueryDoId = 100 }

        @($script:ReplayedLines) | Should -Contain "QueryUrl: https://tenant.omada.cloud/api/x"
        @($script:ErrorLines).Count | Should -Be 0
    }
}
