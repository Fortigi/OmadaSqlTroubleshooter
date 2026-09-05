function Invoke-OmadaExecutePipeline {
    <#
    .SYNOPSIS
    Run the whole execute chain - save the query, create the temporary selection object, execute,
    delete the temporary object - as one sequence, and return everything the UI needs to apply it.

    .DESCRIPTION
    Issue #40, C1-5: "the UI thread never blocks on a network call". The execute path makes up to
    five dependent round-trips, and each one's inputs depend on the previous one's response, so they
    cannot simply be fired off in parallel.

    The obvious way to make them non-blocking is five separate background requests chained through
    five completions. This is deliberately NOT that, and the reason is the one the issue's own
    analysis identifies as the danger of this slice: between completions, Set-ActiveTabContext can
    repoint $Script:MainForm.Elements, $Script:RunTimeData and $Script:AppConfig onto a different
    tab. Five completions means five places where the chain can resume against the wrong tab. One
    background job means ONE completion - exactly the number the path already had after C1-3 - so
    the tab-context risk of this slice is not managed, it is removed.

    The whole function is runspace-safe: no $Script: reads, no logging, no WPF, no calls into this
    module beyond New-OmadaQueryRequest and Invoke-OmadaRequestCore, which are equally pure. What it
    cannot do - writing the config, the dropdown, the grid, the log - it does not attempt; it returns
    a description of what happened and the UI thread applies it.

    Every URL and body comes from New-OmadaQueryRequest, the same builder Save-Query,
    New-TemporarySqlQueryObject and Remove-SqlQueryObject use on the UI thread. There is exactly one
    definition of each request, so the inline and background paths cannot drift apart.

    .PARAMETER Context
    Plain values gathered on the UI thread - see New-OmadaQueryRequest for the keys. Additionally:
      Parameters   the prepared Invoke-OmadaRestMethod splat (Uri, Method and Body are overwritten
                   per step; everything else - SessionKey, authentication, redaction - carries).
      SkipSave     $true to leave the query untouched (nothing to save).

    .OUTPUTS
    Hashtable:
      SaveResult     the response to the save, or $null when no save was needed
      SaveSkipped    $true when nothing had changed, so no save request was made
      TempQueryDoId  the temporary object's id when one was created, else $null
      QueryResult    the execute response
      ErrorRecord    the first failure, or $null
      FailedStep     which step failed, or $null
      CompletedSteps how many requests came back without an error
      Steps          an ordered trace of @{ Name; Method; Uri }
      Log            an ordered list of log entries for the UI thread to replay - see below
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $Outcome = @{
        SaveResult     = $null
        SaveSkipped    = $false
        TempQueryDoId  = $null
        QueryResult    = $null
        ErrorRecord    = $null
        FailedStep     = $null
        Steps          = [System.Collections.Generic.List[object]]::new()
        # How many requests came back WITHOUT an error. The caller uses this to tell "the worker
        # could not talk to the tenant at all" from "the tenant refused something": only the first is
        # safe to retry on the UI thread, because only then is it certain that nothing was changed
        # server-side by the attempt.
        CompletedSteps = 0
        # What the worker WOULD have logged, had it been able to. Replayed verbatim on the UI thread
        # by Complete-ExecuteQueryPipeline, at these levels, so the log of a background execute reads
        # the same as it did when every request was made inline. Without this, moving the chain into a
        # worker silently cost this application most of its diagnostic value - which for a
        # troubleshooting tool is not an acceptable trade for responsiveness.
        Log            = [System.Collections.Generic.List[object]]::new()
    }

    # Entries carry either finished text, or an object plus a format string. The object form exists
    # because redaction (ConvertTo-RedactedLogString) is a UI-thread function and must stay one: the
    # worker records WHAT to log, the UI thread decides how much of it may be written down.
    $Log = {
        param($Level, $Text)
        $Outcome.Log.Add(@{ Level = $Level; Text = $Text })
    }
    $LogObject = {
        param($Level, $Format, $Object, $ShapeOnly)
        $Outcome.Log.Add(@{ Level = $Level; Format = $Format; Redact = $Object; ShapeOnly = [bool]$ShapeOnly })
    }

    # One local helper rather than a call out to another file: this runs in a worker runspace, and
    # every extra name it depends on is another thing that has to be dot-sourced there.
    $Invoke = {
        param($StepName, $Request)
        $Parameters = $Context.Parameters.Clone()
        $Parameters.Uri = $Request.Uri
        $Parameters.Method = $Request.Method
        if ($null -eq $Request.Body) {
            if ($Parameters.ContainsKey("Body")) { $Parameters.Remove("Body") }
        }
        else {
            $Parameters.Body = $Request.Body
        }

        $Outcome.Steps.Add(@{ Name = $StepName; Method = $Request.Method; Uri = $Request.Uri })

        # The same three lines the inline path wrote before every request, in the same order and at
        # the same levels.
        & $Log "DEBUG" ("QueryUrl: {0}" -f $Request.Uri)
        if ($null -ne $Request.Body) {
            & $LogObject "VERBOSE" "Body: {0}" $Request.Body $true
        }
        & $LogObject "VERBOSE" "Parameters: {0}" $Parameters $false

        $StepOutcome = Invoke-OmadaRequestCore -Parameters $Parameters

        if ($null -eq $StepOutcome.ErrorRecord) {
            $Outcome.CompletedSteps = $Outcome.CompletedSteps + 1
            & $LogObject "VERBOSE" "Result: {0}" $StepOutcome.Result $false
        }
        else {
            # DEBUG, not ERROR: the pipeline reports its failure through the outcome, and the caller
            # decides how loudly to say so. An ERROR written from here would be written twice.
            & $Log "DEBUG" ("Step '{0}' failed: {1}" -f $StepName, $StepOutcome.ErrorRecord.Exception.Message)
        }
        return $StepOutcome
    }

    try {
        # --- 1. Save the current query -------------------------------------------------------------
        # The server's copy is fetched first because the decision to save at all depends on it:
        # Save-Query has always compared the editor text against C_QUERY as well as against what this
        # session last saved.
        if (-not $Context.SkipSave) {
            & $Log "INFO" ("Retrieve query {0}" -f $Context.QueryDoId)
            $Private:Fetch = & $Invoke "GetQueryObject" (@{
                    Method = "GET"
                    Uri    = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Context.BaseUrl, $Context.QueryDoId
                    Body   = $null
                })
            if ($null -ne $Private:Fetch.ErrorRecord) {
                $Outcome.ErrorRecord = $Private:Fetch.ErrorRecord
                $Outcome.FailedStep = "GetQueryObject"
                return $Outcome
            }

            $Private:SaveContext = $Context.Clone()
            $Private:SaveContext.SavedQueryText = $Private:Fetch.Result.C_QUERY
            $Private:SaveRequest = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context $Private:SaveContext

            if ($null -eq $Private:SaveRequest) {
                # "No changes detected! Saving not needed." - the caller still needs the fetched
                # object, because it carries the display name the completion reads.
                & $Log "DEBUG" "No changes detected! Saving not needed."
                $Outcome.SaveSkipped = $true
                $Outcome.SaveResult = $Private:Fetch.Result
            }
            else {
                & $Log "INFO" "Save query"
                $Private:Save = & $Invoke "SaveQuery" $Private:SaveRequest
                if ($null -ne $Private:Save.ErrorRecord) {
                    $Outcome.ErrorRecord = $Private:Save.ErrorRecord
                    $Outcome.FailedStep = "SaveQuery"
                    return $Outcome
                }
                $Outcome.SaveResult = $Private:Save.Result
            }
        }

        # --- 2. The temporary object, for an execute-selection run ---------------------------------
        if (![string]::IsNullOrWhiteSpace($Context.SelectionText)) {
            & $Log "DEBUG" "Execute selection mode: creating temporary query object"
            $Private:ReuseDoId = $null

            # A probe failure is not fatal, exactly as it is not on the UI thread: the existing
            # New-TemporarySqlQueryObject swallows it and falls through to creating a new object.
            $Private:Probe = & $Invoke "TempQueryProbe" (New-OmadaQueryRequest -Kind "TempQueryProbe" -Context $Context)
            if ($null -eq $Private:Probe.ErrorRecord -and
                $null -ne $Private:Probe.Result -and $null -ne $Private:Probe.Result.Value -and
                @($Private:Probe.Result.Value).Count -gt 0 -and
                ![string]::IsNullOrWhiteSpace($Private:Probe.Result.Value[0].Id)) {

                $Private:ReuseDoId = $Private:Probe.Result.Value[0].Id

                if ($Private:Probe.Result.Value[0].Deleted -eq $true) {
                    $Private:UndeleteContext = $Context.Clone()
                    $Private:UndeleteContext.TempQueryDoId = $Private:ReuseDoId
                    # Also non-fatal: the upsert below is a PUT that will fail loudly if the object
                    # really is unusable.
                    [void](& $Invoke "TempQueryUndelete" (New-OmadaQueryRequest -Kind "TempQueryUndelete" -Context $Private:UndeleteContext))
                }
            }

            $Private:UpsertContext = $Context.Clone()
            $Private:UpsertContext.TempQueryDoId = $Private:ReuseDoId
            $Private:Upsert = & $Invoke "TempQueryUpsert" (New-OmadaQueryRequest -Kind "TempQueryUpsert" -Context $Private:UpsertContext)

            if ($null -ne $Private:Upsert.ErrorRecord) {
                $Outcome.ErrorRecord = $Private:Upsert.ErrorRecord
                $Outcome.FailedStep = "TempQueryUpsert"
                return $Outcome
            }

            # A PUT onto the reused object answers without an Id, so fall back to the id that was
            # reused - it is the object the query must run against either way.
            $Outcome.TempQueryDoId = if ($null -ne $Private:Upsert.Result -and $null -ne $Private:Upsert.Result.Id) { $Private:Upsert.Result.Id } else { $Private:ReuseDoId }

            # Published to the UI thread the moment it is known, through the synchronized table
            # Start-OmadaBackgroundRequest put on the pending item. Cancellation kills this frame
            # outright, so the finally below never runs - and without this the UI would have no idea
            # which object to clean up. It is the one piece of state that has to escape the worker
            # before the worker finishes.
            if ($null -ne $Context.Progress) {
                $Context.Progress.TempQueryDoId = $Outcome.TempQueryDoId
            }

            if ($null -eq $Outcome.TempQueryDoId) {
                $Outcome.FailedStep = "TempQueryUpsert"
                return $Outcome
            }
        }

        # --- 3. The query itself -------------------------------------------------------------------
        $Private:ExecuteContext = $Context.Clone()
        $Private:ExecuteContext.TargetQueryDoId = if ($null -ne $Outcome.TempQueryDoId) { $Outcome.TempQueryDoId } else { $Context.QueryDoId }
        & $Log "INFO" "Retrieve query output, please wait..."
        $Private:Execute = & $Invoke "ExecuteQuery" (New-OmadaQueryRequest -Kind "ExecuteQuery" -Context $Private:ExecuteContext)

        if ($null -ne $Private:Execute.ErrorRecord) {
            $Outcome.ErrorRecord = $Private:Execute.ErrorRecord
            $Outcome.FailedStep = "ExecuteQuery"
        }
        else {
            $Outcome.QueryResult = $Private:Execute.Result
        }

        return $Outcome
    }
    catch {
        $Outcome.ErrorRecord = $_
        if ($null -eq $Outcome.FailedStep) { $Outcome.FailedStep = "Pipeline" }
        return $Outcome
    }
    finally {
        # The temporary object is deleted here, in a finally, and not by the caller: it must go
        # whether the query succeeded, failed or threw. Leaving it is how a TMP_<guid> ends up
        # stranded on someone's tenant. Its own failure is swallowed - there is nothing useful to do
        # about it from in here, and it must not mask the real error being returned above.
        #
        # Cancellation is the one case this cannot cover: stopping the pipeline kills this frame
        # outright. Stop-ExecuteQueryRequest deletes it from the UI thread instead, which is why the
        # id is also reported back on the pending item.
        if ($null -ne $Outcome.TempQueryDoId) {
            try {
                $Private:DeleteContext = $Context.Clone()
                $Private:DeleteContext.TempQueryDoId = $Outcome.TempQueryDoId
                [void](& $Invoke "DeleteTempQuery" (New-OmadaQueryRequest -Kind "DeleteQuery" -Context $Private:DeleteContext))
                # Cleared so the UI does not delete it a second time on a cancellation that raced
                # this frame.
                if ($null -ne $Context.Progress) {
                    $Context.Progress.TempQueryDoId = $null
                }
            }
            catch { }
        }
    }
}
