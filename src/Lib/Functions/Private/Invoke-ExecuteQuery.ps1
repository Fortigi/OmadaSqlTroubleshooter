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
            $Private:TempQueryDoId = $null
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

                    $Private:Result = Save-Query -NewQuery:$false

                    $Private:ExecutionTargetId = $Script:AppConfig.CurrentSqlQuery.DoId
                    if (![string]::IsNullOrWhiteSpace($Private:SelectionText)) {
                        "Execute selection mode: creating temporary query object" | Write-LogOutput -LogType DEBUG
                        $Private:TempQueryDoId = New-TemporarySqlQueryObject -QueryText $Private:SelectionText
                        if ($null -ne $Private:TempQueryDoId) {
                            $Private:ExecutionTargetId = $Private:TempQueryDoId
                        }
                        else {
                            "Failed to create temporary query object for selection execution." | Write-LogOutput -LogType ERROR
                            return
                        }
                    }

                    $Script:RunTimeData.RestMethodParam.Uri = "{0}/webservice/jQGridPopulationWebService.asmx/GetPagingData" -f $Script:AppConfig.BaseUrl

                    $Script:RunTimeData.RestMethodParam.Body = @{
                        "dataType"     = "SqlDataProducer"
                        "dataTypeArgs" = @{
                            "targetId" = $Private:ExecutionTargetId
                        }
                        "page"         = 1
                        "rows"         = 100000
                        "sidx"         = $null
                        "sord"         = "asc"
                        "_search"      = $false
                        "searchField"  = $null
                        "searchString" = $null
                        "filters"      = $null
                        "searchOper"   = $null
                    }
                    "Body: {0}" -f (ConvertTo-RedactedLogString -InputObject $Script:RunTimeData.RestMethodParam.Body -ShapeOnly) | Write-LogOutput -LogType VERBOSE
                    "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

                    "Retrieve query output, please wait..." | Write-LogOutput
                    $Script:RunTimeData.RestMethodParam.Method = "POST"
                    $Script:RunTimeData.QueryResult = $null

                    # The headline of issue #40: THIS is the call that freezes the window, and it is
                    # the one that now runs on a background worker. Everything above it - reading the
                    # editor, the syntax gate, saving the query, creating the temporary object - is
                    # still synchronous, and deliberately so: those are short calls, and two of them
                    # can open a modal dialog, which belongs on the UI thread. Moving the remaining
                    # round-trips off-thread is C1-5, a separate slice with a much larger blast radius.
                    #
                    # Everything the completion needs travels on the context. It must not re-read
                    # $Script: state: by the time the response lands the user may be looking at
                    # another tab, and $Private:Result (the Save-Query outcome) and the temporary
                    # object id do not exist anywhere else.
                    $Private:Pending = Invoke-OmadaPSWebRequestWrapperAsync -Description "Execute query" -Context @{
                        SaveResult    = $Private:Result
                        TempQueryDoId = $Private:TempQueryDoId
                    } -OnResultScriptBlock {
                        param($Pending)
                        Complete-ExecuteQueryResult -QueryResult $Pending.Outcome -SaveResult $Pending.Context.Caller.SaveResult -TempQueryDoId $Pending.Context.Caller.TempQueryDoId
                    }

                    if ($null -ne $Private:Pending) {
                        # Dispatched. Ownership of the temporary object passes to the completion, so
                        # this frame must forget it - otherwise the catch below would delete an object
                        # the in-flight query is still executing against.
                        $Private:TempQueryDoId = $null
                        return
                    }

                    # Not eligible for a worker, or none available: run it inline, exactly as before.
                    $Private:QueryResult = Invoke-OmadaPSWebRequestWrapper
                    $Private:CompletedTempQueryDoId = $Private:TempQueryDoId
                    $Private:TempQueryDoId = $null
                    Complete-ExecuteQueryResult -QueryResult $Private:QueryResult -SaveResult $Private:Result -TempQueryDoId $Private:CompletedTempQueryDoId
                    return
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }
                Reset-ExecuteQueryUiState
            }
            catch {
                if ($null -ne $Private:TempQueryDoId) {
                    Remove-SqlQueryObject -DoId $Private:TempQueryDoId
                }
                Reset-ExecuteQueryUiState
                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        Reset-ExecuteQueryUiState
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}

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
        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true

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
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
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

        if ($null -ne $Script:RunTimeData.QueryResult -and ($Script:RunTimeData.QueryResult.d.Rows | Measure-Object).Count -le 0) {
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
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
