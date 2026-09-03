function Invoke-ExecuteQuery {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        # selectionStartLine/Column come back so the syntax pass can put its markers where the
        # selected text actually sits in the model; the parser only ever sees the selection, so it
        # numbers the selection's first line as line 1.
        $ScriptToExecute = "(function() { var fullText = editor.getValue(); var sel = editor.getSelection(); var hasSelection = sel && !sel.isEmpty(); var selectedText = hasSelection ? editor.getModel().getValueInRange(sel) : null; return { fullText: fullText, selectedText: selectedText, selectionStartLine: hasSelection ? sel.startLineNumber : 1, selectionStartColumn: hasSelection ? sel.startColumn : 1 }; })();"

        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $Private:EditorData = $Script:Task.Result | ConvertFrom-Json
                    $Script:RunTimeData.QueryText = $Private:EditorData.fullText
                    $Private:SelectionText = $Private:EditorData.selectedText

                    # Client-side syntax gate (issue #61). Checks the text that will actually run -
                    # the selection when there is one - refreshes the editor's markers from it, and
                    # asks once before spending a round trip on a batch SQL Server will reject
                    # before it touches a table. It NEVER blocks: parser version and server version
                    # can legitimately disagree, so declining is a choice, not an error.
                    $Private:TextToValidate = $Private:EditorData.fullText
                    if (![string]::IsNullOrWhiteSpace($Private:SelectionText)) {
                        $Private:TextToValidate = $Private:SelectionText
                    }

                    $Private:ValidationSetting = Get-SqlValidationSetting
                    if ($Private:ValidationSetting.Enabled) {
                        $Private:SyntaxResult = Get-SqlSyntaxDiagnostic -SqlText $Private:TextToValidate -ParserVersion $Private:ValidationSetting.ParserVersion

                        # Markers are refreshed either way. A parse that could not run clears them:
                        # anything still on screen came from an earlier parse of different text, and
                        # a stale squiggle is indistinguishable from a live one.
                        $Private:SyntaxDiagnostic = @()
                        if ($Private:SyntaxResult.Status -eq "Ok") {
                            $Private:SyntaxDiagnostic = $Private:SyntaxResult.Diagnostic

                            # The parser numbered the selection from line 1. The markers go onto the
                            # whole model, so without this every squiggle for an executed selection
                            # lands too high by the height of the text above it.
                            if (![string]::IsNullOrWhiteSpace($Private:SelectionText)) {
                                $Private:SyntaxDiagnostic = Move-SqlDiagnosticToSelection -Diagnostic $Private:SyntaxDiagnostic -StartLine $Private:EditorData.selectionStartLine -StartColumn $Private:EditorData.selectionStartColumn
                            }
                        }

                        Invoke-ExecuteScriptAsync -ScriptToExecute (ConvertTo-EditorDiagnosticScript -Diagnostic $Private:SyntaxDiagnostic)

                        # Only a completed parse can ask a question. A parse that did not run has
                        # nothing to warn about and must not stand between the user and their query.
                        if (($Private:SyntaxDiagnostic | Measure-Object).Count -gt 0 -and $Private:ValidationSetting.WarnOnExecuteWithErrors) {
                            "Query has {0} syntax diagnostic(s); asking before executing." -f ($Private:SyntaxDiagnostic | Measure-Object).Count | Write-LogOutput -LogType DEBUG
                            $Private:Confirmed = Open-ChoiceForm -Title "Syntax errors" -Message (Get-SqlSyntaxWarningMessage -Diagnostic $Private:SyntaxDiagnostic) -LeftButtonText "Execute anyway" -RightButtonText "Cancel"
                            if ($Private:Confirmed -ne $true) {
                                "Execution cancelled by the user after the syntax check." | Write-LogOutput -LogType DEBUG
                                Reset-ExecuteQueryUiState
                                return
                            }
                        }
                    }

                    # C1-5: the whole dependent chain - fetch the query, save it if it changed,
                    # create the temporary selection object, execute, delete the temporary object -
                    # runs as ONE background job. Up to five round-trips, none of them on the UI
                    # thread, and still only ONE completion.
                    #
                    # That last part is the design decision worth reviewing. The obvious way to make
                    # five dependent calls non-blocking is five dispatches chained through five
                    # completions; issue #40's own analysis names the danger of doing that here, and
                    # it is real: Set-ActiveTabContext can repoint $Script:MainForm.Elements,
                    # $Script:RunTimeData and $Script:AppConfig between completions, so every extra
                    # completion is another place the chain can resume against the wrong tab. One job
                    # means one repoint - the same number this path already had after C1-3.
                    #
                    # The context is gathered HERE, on the UI thread, as plain values. The worker gets
                    # no $Script: state and no WPF, and returns a description of what happened for the
                    # completion to apply.
                    $Private:PipelineContext = @{
                        BaseUrl            = $Script:AppConfig.BaseUrl
                        QueryDoId          = $Script:AppConfig.CurrentSqlQuery.DoId
                        QueryText          = $Script:RunTimeData.QueryText
                        CurrentQueryText   = $Script:RunTimeData.CurrentQueryText
                        DisplayName        = $Script:MainForm.Elements.TextBoxDisplayName.Text
                        CurrentDisplayName = $Script:RunTimeData.CurrentSqlQuery.DisplayName
                        DataConnectionDoId = $Script:AppConfig.CurrentDataConnection.DoId
                        SelectionText      = $Private:SelectionText
                        TempName           = "TMP_$($Script:RunTimeConfig.InstanceGuid)"
                        SkipSave           = $false
                    }

                    "Retrieve query output, please wait..." | Write-LogOutput

                    # The context travels on the pending item as well as into the worker, so a
                    # completion that finds the worker could not run the chain can re-run it inline.
                    # On the item rather than in module scope: two tabs can have a query in flight at
                    # once, and a shared slot would hand one tab's retry the other tab's query.
                    $Private:Pending = Invoke-OmadaPSWebRequestWrapperAsync -Description $Script:ExecuteQueryRequestDescription -PipelineContext $Private:PipelineContext -Context @{
                        PipelineContext = $Private:PipelineContext
                    } -OnResultScriptBlock {
                        param($Pending)
                        Complete-ExecuteQueryPipeline -Outcome $Pending.Outcome -PipelineContext $Pending.Context.Caller.PipelineContext
                    }

                    if ($null -ne $Private:Pending) {
                        # The Execute button becomes Cancel: from here the only useful thing the user
                        # can do with it is stop waiting.
                        Set-ExecuteQueryButtonState
                        return
                    }

                    # No worker available, or the tab is not eligible for one: run the identical
                    # chain inline. Slower - it blocks, exactly as the app did before #40 - but the
                    # same requests in the same order, because it is literally the same function.
                    $Private:PipelineContext.Parameters = Build-OmadaRequestParameter
                    Complete-ExecuteQueryPipeline -Outcome (Invoke-OmadaExecutePipeline -Context $Private:PipelineContext)
                    return
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    # "Task failed: Faulted" - which is what this used to say - tells the reader only
                    # that the status is the status. A faulted Task carries an AggregateException, so
                    # the message worth having is the base exception's, not the wrapper's.
                    $Private:TaskFailure = "no exception was recorded"
                    if ($null -ne $Script:Task.Exception) {
                        $Private:TaskFailure = $Script:Task.Exception.GetBaseException().Message
                    }

                    "Reading the editor's contents failed: {0}" -f $Private:TaskFailure | Write-ContainedErrorLog -ErrorObject $Script:Task.Exception
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }
                Reset-ExecuteQueryUiState
            }
            catch {
                # No temporary-object clean-up here any more: since C1-5 the pipeline owns that
                # object for its whole lifetime and deletes it in its own finally, so this frame
                # never holds one to leak.
                Reset-ExecuteQueryUiState
                $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        Reset-ExecuteQueryUiState
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

# The label an execute request carries on the completion queue. A constant because it is matched,
# not just displayed: Get-ActiveExecuteQueryRequest reads the queue through it to decide whether the
# active tab is executing, which is what drives the Execute/Cancel button.
$Script:ExecuteQueryRequestDescription = "Execute query"

function Reset-ExecuteQueryUiState {
    <#
    .SYNOPSIS
    Return the active tab to a state where the user can execute again: buttons re-enabled, the
    "Executing Query..." popup closed, the stopwatch stopped and its final value on the status bar.

    .DESCRIPTION
    The same teardown was written out five times across Invoke-ExecuteQuery, in slightly different
    forms - one of them forgot the stopwatch, another forgot the status bar. Issue #40 adds a sixth
    caller (the completion of a background request) and C1-4 will add a seventh (Cancel), which is
    more copies than a block this easy to get subtly wrong should have.

    Deliberately does NOT touch DataGridQueryResult: a failed or abandoned execute must leave the
    previous result on screen rather than blanking it.

    .PARAMETER SkipStatusBarTime
    Stop the stopwatch without writing its value to the status bar. Used where the elapsed time is
    not meaningful - a run that never issued a request.
    #>
    [CmdLetBinding()]
    param(
        [switch]$SkipStatusBarTime
    )

    try {
        # Only for a tab that is still connected. A query can now outlive the connection it was
        # issued on - the user can disconnect, or a 401 can tear the tab down through
        # Set-SqlConnectionState, while the request is in flight - and the completion still runs
        # afterwards. Re-enabling here unconditionally would hand a disconnected tab a live Execute
        # and Save button: the "in-between tab state" of issue #65, arrived at from a new direction.
        # Set-SqlQueryFunctionState remains the single writer of these when disconnected.
        if ($Script:ConnectionStatus) {
            $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
        }

        # Back to "Execute" either way: a tab must never be left showing Cancel with nothing to
        # cancel, connected or not. By the time any caller reaches this the request is off the queue -
        # drained by the poll timer, or removed by Stop-ExecuteQueryRequest before it called here.
        Set-ExecuteQueryButtonState

        if ($null -ne $Script:PopupWindowExecuteQuery) {
            $Script:PopupWindowExecuteQuery.Close()
            $Script:PopupWindowExecuteQuery = $null
        }

        if ($null -ne $Script:RunTimeData.StopWatch) {
            $Script:RunTimeData.StopWatch.Stop()
            if (-not $SkipStatusBarTime) {
                "Elapsed time: {0}" -f $Script:RunTimeData.StopWatch.Elapsed.ToString() | Write-LogOutput -LogType DEBUG
                $Script:MainForm.Elements.TextBlockStatusBarQueryTime.Text = $Script:RunTimeData.StopWatch.Elapsed.ToString()
            }
        }
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Invoke-ExecuteQueryOnUiThread {
    <#
    .SYNOPSIS
    Re-run the execute chain synchronously after a background worker failed to run it at all, and
    stop offering background execution for the rest of the session.

    .DESCRIPTION
    The half of issue #40's authentication policy that was designed but never built. The policy was:
    interactive authentication happens on the UI thread, and "a 401 returned to the UI thread from a
    worker is re-driven on the UI thread". Only the gate was implemented -
    Test-OmadaBackgroundRequestEligible - which assumed a connected tab's session would be
    recoverable in a worker from OmadaWeb.PS's encrypted cookie cache.

    Live-tenant testing showed the assumption does not hold for every tenant and authentication
    option: the worker's own OmadaWeb.PS instance could not establish a session, so every background
    request failed. Because the failure was then reported through the empty-result path, the user saw
    "Query did not return any results!" on every execute and the real error was never logged.

    So the re-drive is built now, and it does two things:

      - runs the identical chain inline, so the user gets their result. It is the same function the
        worker runs, with the same context, so the requests and their order are identical - just
        slower, and blocking, exactly as the application behaved before #40.
      - disables background execution for the session, so the next query does not pay for another
        doomed round-trip before falling back again.

    Only ever called when NOTHING reached the tenant, so re-running cannot repeat work the server has
    already done.

    .PARAMETER PipelineContext
    The context the failed request was dispatched with, carried on the pending item rather than held
    in module scope - two tabs can have a query in flight at once, and a single shared slot would
    hand one tab's retry the other tab's query.

    .PARAMETER Reason
    Why the worker could not run it, for the single warning Disable-OmadaBackgroundRequest writes.
    #>
    [CmdLetBinding()]
    param(
        [hashtable]$PipelineContext,
        [string]$Reason
    )

    try {
        # A tab that is no longer connected must not be retried against. Resolve-OmadaRequestFailure
        # tears the tab down through Set-SqlConnectionState for the two tenant-level failures
        # (Unauthorized, OData endpoint missing) and then throws - and the completion still runs,
        # because the async wrapper invokes it in a finally. Those are the tenant's answer, not a
        # worker that could not do its job: retrying would fail again at best, and disabling
        # background execution over an expired session would be the wrong conclusion entirely.
        # $Script:ConnectionStatus is the signal, and it also covers the user disconnecting while a
        # query was in flight.
        if (-not $Script:ConnectionStatus) {
            "Not retrying the query on the UI thread: the tab is no longer connected." | Write-LogOutput -LogType DEBUG
            Complete-ExecuteQueryResult -QueryResult $null -SaveResult $null -TempQueryDoId $null
            return
        }

        Disable-OmadaBackgroundRequest -Reason $Reason

        if ($null -eq $PipelineContext) {
            # Nothing to re-run with. Reported rather than silently ignored: this would mean the
            # context was lost between dispatch and completion, which is a bug here rather than a
            # problem at the tenant.
            "Cannot retry the query on the UI thread: the request context is no longer available." | Write-ContainedErrorLog
            Complete-ExecuteQueryResult -QueryResult $null -SaveResult $null -TempQueryDoId $null
            return
        }

        "Retrying the query on the UI thread." | Write-LogOutput -LogType DEBUG
        $Private:RetryContext = $PipelineContext.Clone()
        $Private:RetryContext.Parameters = Build-OmadaRequestParameter
        Complete-ExecuteQueryPipeline -Outcome (Invoke-OmadaExecutePipeline -Context $Private:RetryContext)
    }
    catch {
        Reset-ExecuteQueryUiState
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Complete-ExecuteQueryPipeline {
    <#
    .SYNOPSIS
    Apply the outcome of an execute pipeline on the UI thread: log what it did, then bind the result.

    .DESCRIPTION
    The UI half of C1-5. Invoke-OmadaExecutePipeline cannot log, cannot touch WPF and cannot write
    the config, so it returns a description of what happened and this applies it - from the
    completion poll timer, with the owning tab already made active.

    Everything it needs is in $Outcome. It deliberately re-reads nothing from $Script: state that the
    pipeline already decided: by the time this runs the user may be looking at another tab, and the
    save result in particular exists nowhere else.

    .PARAMETER Outcome
    The pipeline's outcome hashtable - or an ErrorRecord, when the failure was one of the two
    tenant-level kinds Resolve-OmadaRequestFailure classifies and returns in place of a result.

    .PARAMETER PipelineContext
    The context the request was dispatched with. Only used to re-run the chain on the UI thread when
    the worker could not run it at all; $null on the inline path, which has nothing to fall back to.
    #>
    [CmdLetBinding()]
    param(
        $Outcome,
        [hashtable]$PipelineContext
    )

    try {
        # The worker produced no outcome object at all - it could not run the chain. That is not a
        # result, and reporting it as one is what made a failed query look like an empty one.
        if ($Outcome -is [System.Management.Automation.ErrorRecord] -or $null -eq $Outcome -or $null -eq $Outcome.Steps) {
            $Private:Reason = if ($Outcome -is [System.Management.Automation.ErrorRecord]) { $Outcome.Exception.Message } else { "the background worker returned no result" }
            "The query could not be run on a background worker: {0}" -f $Private:Reason | Write-LogOutput -LogType DEBUG
            Invoke-ExecuteQueryOnUiThread -PipelineContext $PipelineContext -Reason $Private:Reason
            return
        }

        # Everything the worker would have written to the log, replayed here at the levels it chose.
        # A worker cannot log - no $Script: state, no log file, no window - so without this, moving
        # the chain off the UI thread silently cost this application most of its diagnostic value.
        # For a troubleshooting tool that is not an acceptable price for responsiveness.
        #
        # Redaction happens HERE, not in the worker: ConvertTo-RedactedLogString is a UI-thread
        # function and stays one, so there is a single place that decides how much of a request or a
        # response may be written down. The worker records what to log; this decides what is safe.
        Write-ExecutePipelineLog -Log $Outcome.Log

        if ($null -ne $Outcome.SaveResult -and -not $Outcome.SaveSkipped) {
            "Query saved!" | Write-LogOutput
        }

        if ($null -ne $Outcome.ErrorRecord) {
            # Nothing reached the tenant: the very first request failed, so no query ran, nothing was
            # saved and no temporary object exists. The worker could not do its job - almost always
            # because its own OmadaWeb.PS instance has no session - and the UI thread can, so run it
            # there rather than telling the user their query returned nothing.
            #
            # Gated on CompletedSteps precisely so this cannot re-run work the tenant already did. If
            # any step succeeded, the failure is the tenant's answer and is reported as such.
            if ([int]$Outcome.CompletedSteps -le 0) {
                "The query could not be run on a background worker: {0}" -f $Outcome.ErrorRecord.Exception.Message | Write-LogOutput -LogType DEBUG
                Invoke-ExecuteQueryOnUiThread -PipelineContext $PipelineContext -Reason $Outcome.ErrorRecord.Exception.Message
                return
            }

            "The query pipeline failed at step '{0}': {1}" -f $Outcome.FailedStep, $Outcome.ErrorRecord.Exception.Message | Write-ContainedErrorLog -ErrorObject $Outcome.ErrorRecord
            Complete-ExecuteQueryResult -QueryResult $Outcome.ErrorRecord -SaveResult $Outcome.SaveResult -TempQueryDoId $null
            return
        }

        # TempQueryDoId is passed as $null on purpose: the pipeline already deleted the temporary
        # object in its own finally, whatever the outcome. Passing it would delete it twice.
        Complete-ExecuteQueryResult -QueryResult $Outcome.QueryResult -SaveResult $Outcome.SaveResult -TempQueryDoId $null
    }
    catch {
        Reset-ExecuteQueryUiState
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Complete-ExecuteQueryResult {
    <#
    .SYNOPSIS
    Everything that happens once a query result is in hand: clean up the temporary object, bind the
    grid, update the status bar and the query list, and return the UI to a usable state.

    .DESCRIPTION
    Split out of Invoke-ExecuteQuery by issue #40 so identical work runs whether the response arrived
    from a background worker or inline. UI thread only, which it always is: the background path
    reaches it from the completion poll timer, with the owning tab already made active by
    Set-ActiveTabContext.

    .PARAMETER QueryResult
    What the request produced: the response object, an ErrorRecord, or $null.

    .PARAMETER SaveResult
    The object Save-Query returned earlier in this execution. Passed in rather than re-read, because
    it exists nowhere else and the frame that produced it has long since returned.

    .PARAMETER TempQueryDoId
    The temporary TMP_<guid> object created for an "execute selection" run, or $null. Deleted here,
    and deleted whatever the outcome - a result that never arrived still leaves an object behind on
    the tenant.
    #>
    [CmdLetBinding()]
    param(
        $QueryResult,
        $SaveResult,
        $TempQueryDoId
    )

    try {
        $Script:RunTimeData.QueryResult = $QueryResult

        if ($null -ne $TempQueryDoId) {
            Remove-SqlQueryObject -DoId $TempQueryDoId
        }

        $Script:DataGridQueryResultColumnSelectionAnchor = $null

        # "-eq $null -or", not "-ne $null -and". A null result used to fall through to the binding
        # branch, where @($null.d.Rows) is a one-element array containing $null: the grid was bound to
        # a phantom row and the Show output / Save output buttons were enabled for a result that does
        # not exist. Null became far more reachable once a request could fail or be abandoned in a
        # worker, so it is now treated as what it is - no rows.
        if ($null -eq $Script:RunTimeData.QueryResult -or ($Script:RunTimeData.QueryResult.d.Rows | Measure-Object).Count -le 0) {
            "Query did not return any results!" | Write-LogOutput -LogType WARNING
            $Script:MainForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "0 rows"
            $Script:MainForm.Elements.DataGridQueryResult.ItemsSource = $null
        }
        else {
            $Script:MainForm.Elements.DataGridQueryResult.AutoGenerateColumns = $true
            try {
                $Script:MainForm.Elements.DataGridQueryResult.ItemsSource = @($Script:RunTimeData.QueryResult.d.Rows)
            }
            catch {
                #Work-around issue that Omada can return invalid JSON keys.
                $Script:MainForm.Elements.DataGridQueryResult.ItemsSource = @(($Script:RunTimeData.QueryResult | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10).d.Rows)
            }
            "Result: {0}" -f (Get-LogResultShape -InputObject $Script:RunTimeData.QueryResult.d.rows) | Write-LogOutput -LogType VERBOSE2
            $Script:MainForm.Elements.ButtonShowOutput.IsEnabled = $true
            $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled = $true
            "{0} record(s) retrieved!" -f $Script:RunTimeData.QueryResult.d.Records | Write-LogOutput

            $Script:MainForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text ("{0:n0} rows" -f [Int]$Script:RunTimeData.QueryResult.d.Records)
            $SaveResult.Id, $SaveResult.DisplayName | Set-ConfigProperty -Property "CurrentSqlQuery"
            if ($SaveResult.DisplayName -ne $Script:RunTimeData.CurrentSqlQuery.DisplayName) {
                "New display name, Current: {0}, New: {1}" -f $Script:RunTimeData.CurrentSqlQuery.DisplayName, $SaveResult.DisplayName | Write-LogOutput -LogType DEBUG
                "Force update query list" | Write-LogOutput -LogType DEBUG
                Update-QueryList -ForceRefresh

                # Find-or-create, then select - the pattern Save-Query and Complete-TabMaterialization
                # already use. This block used to test "$null -ne $ComboBoxSelectQueryItem" against a
                # variable that had never been assigned, so the body was unreachable and the line
                # after it selected $null: executing a renamed query silently CLEARED the query
                # dropdown instead of re-selecting the renamed entry.
                $Private:ComboBoxSelectQueryItem = $Script:MainForm.Elements.ComboBoxSelectQuery.Items |
                    Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" } |
                    Select-Object -First 1

                if ($null -eq $Private:ComboBoxSelectQueryItem) {
                    $Private:ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $Private:ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                    $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($Private:ComboBoxSelectQueryItem) | Out-Null
                }

                $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $Private:ComboBoxSelectQueryItem
            }
        }

        Reset-ExecuteQueryUiState
    }
    catch {
        # The temporary object is already gone by here - it is deleted before anything that can throw
        # - so this only has to put the UI back.
        Reset-ExecuteQueryUiState
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
