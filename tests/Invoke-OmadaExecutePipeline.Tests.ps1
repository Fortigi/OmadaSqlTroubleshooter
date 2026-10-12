#Requires -Version 7.0
# The execute chain as one background job (issue #40, C1-5).
#
# These are the tests that matter most in this slice, because the pipeline is where five dependent
# round-trips are sequenced and where the temporary object's lifetime is decided. Each case asserts
# the ORDER and SHAPE of the requests it made, using a recording transport - so a change to the
# sequencing fails here rather than on someone's tenant.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "New-OmadaQueryRequest.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaExecutePipeline.ps1")

    # The pipeline's only transport. Recorded, and steerable per step by URI/method.
    $script:Calls = [System.Collections.Generic.List[object]]::new()
    $script:Responses = @{}
    $script:Failures = @{}

    function Invoke-OmadaRequestCore {
        param([hashtable]$Parameters)
        $Key = Get-CallKey -Method $Parameters.Method -Uri $Parameters.Uri -Body $Parameters.Body
        $script:Calls.Add([pscustomobject]@{ Key = $Key; Method = $Parameters.Method; Uri = $Parameters.Uri; Body = $Parameters.Body })

        if ($script:Failures.ContainsKey($Key)) {
            return @{ Result = $null; ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($script:Failures[$Key]), "PipelineTestFailure",
                    [System.Management.Automation.ErrorCategory]::ConnectionError, $null) }
        }
        if ($script:Responses.ContainsKey($Key)) {
            return @{ Result = $script:Responses[$Key]; ErrorRecord = $null }
        }
        return @{ Result = $null; ErrorRecord = $null }
    }

    function script:Get-CallKey {
        # A short, stable name per logical request, so the tests read as a sequence of steps rather
        # than a list of URLs.
        param($Method, $Uri, $Body)
        if ($Uri -like "*GetPagingData*") { return "execute" }
        if ($Uri -like "*UndeleteDataObject*") { return "undelete" }
        if ($Uri -like "*DeletedStatus=Both*") { return "probe" }
        if ($Method -eq "DELETE") { return "delete" }
        if ($Method -eq "GET") { return "get" }
        if ($Method -eq "PUT" -and $Body.ContainsKey("NAME") -and ([string]$Body["NAME"]).StartsWith("TMP_")) { return "temp-put" }
        if ($Method -eq "POST" -and $null -ne $Body -and $Body.ContainsKey("NAME") -and ([string]$Body["NAME"]).StartsWith("TMP_")) { return "temp-post" }
        if ($Method -eq "PUT") { return "save" }
        return "other"
    }

    function script:New-PipelineContext {
        param(
            $QueryText = "SELECT 1",
            $SelectionText = $null,
            $CurrentQueryText = "SELECT 1",
            $DisplayName = "TestQuery",
            $CurrentDisplayName = "TestQuery"
        )
        return @{
            BaseUrl            = "https://tenant.omada.cloud"
            QueryDoId          = 100
            QueryText          = $QueryText
            CurrentQueryText   = $CurrentQueryText
            DisplayName        = $DisplayName
            CurrentDisplayName = $CurrentDisplayName
            DataConnectionDoId = "42"
            SelectionText      = $SelectionText
            TempName           = "TMP_abc"
            SkipSave           = $false
            Parameters         = @{ SessionKey = "pool"; AuthenticationType = "Browser" }
        }
    }

    function script:Get-CallSequence {
        return @($script:Calls | ForEach-Object { $_.Key })
    }

    function script:Reset-PipelineTestState {
        $script:Calls.Clear()
        $script:Failures = @{}
        $script:Responses = @{
            # The stored query, fetched first so the save decision can compare against it.
            "get"       = [pscustomobject]@{ Id = 100; C_QUERY = "SELECT 1"; DisplayName = "TestQuery" }
            "save"      = [pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }
            "probe"     = [pscustomobject]@{ Value = @() }
            "temp-post" = [pscustomobject]@{ Id = 777 }
            "temp-put"  = [pscustomobject]@{ Id = 777 }
            "execute"   = [pscustomobject]@{ d = [pscustomobject]@{ Records = 2; Rows = @(1, 2) } }
        }
    }
}

Describe "Invoke-OmadaExecutePipeline - the ordinary run" {
    BeforeEach { Reset-PipelineTestState }

    It "fetches the query, skips a save that is not needed, and executes" {
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext)

        Get-CallSequence | Should -Be @("get", "execute")
        $Outcome.SaveSkipped | Should -BeTrue
        $Outcome.QueryResult.d.Records | Should -Be 2
        $Outcome.ErrorRecord | Should -BeNullOrEmpty
    }

    It "saves before executing when the query text changed" {
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -QueryText "SELECT 2")

        Get-CallSequence | Should -Be @("get", "save", "execute")
        $Outcome.SaveSkipped | Should -BeFalse
        $Outcome.SaveResult.Id | Should -Be 100
    }

    It "still reports the fetched object when the save was skipped" {
        # The completion needs it: the display name it carries is what decides whether the query list
        # has to be refreshed.
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext)

        $Outcome.SaveResult.DisplayName | Should -Be "TestQuery"
    }

    It "executes against the current query when there is no selection" {
        Invoke-OmadaExecutePipeline -Context (New-PipelineContext) | Out-Null

        $Execute = $script:Calls | Where-Object { $_.Key -eq "execute" } | Select-Object -First 1
        $Execute.Body["dataTypeArgs"]["targetId"] | Should -Be 100
    }

    It "leaves the query alone when the caller asks it to" {
        $Context = New-PipelineContext
        $Context.SkipSave = $true

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        Get-CallSequence | Should -Be @("execute")
    }

    It "reports every step it took, in order, for the UI to log" {
        # The pipeline cannot log - it runs in a worker - so the trace is how the log stays as
        # informative as it was when every request was made inline.
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -QueryText "SELECT 2")

        @($Outcome.Steps | ForEach-Object { $_.Name }) | Should -Be @("GetQueryObject", "SaveQuery", "ExecuteQuery")
    }

    It "records the lines the UI thread has to write on its behalf" {
        # Steps say WHAT ran; Log carries what a person reading the log needs to see - the URL, the
        # body, the parameter set, the response. Before this, moving the chain into a worker silently
        # emptied the log of everything an execute used to record.
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -QueryText "SELECT 2")

        @($Outcome.Log).Count | Should -BeGreaterThan 0
        @($Outcome.Log | Where-Object { $_.Text -match "Retrieve query output" }).Count | Should -Be 1
        @($Outcome.Log | Where-Object { $_.Text -match "Save query" }).Count | Should -Be 1
        @($Outcome.Log | Where-Object { $_.Text -match "QueryUrl" }).Count | Should -BeGreaterThan 0
    }

    It "marks the request body as shape-only, so a query's content is never written verbatim" {
        # Redaction happens on the UI thread, but the DECISION to log a body as a shape is made here.
        # Getting this wrong would put user data in the log file.
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext)

        $Private:BodyEntries = @($Outcome.Log | Where-Object { $_.Format -match "Body" })
        @($Private:BodyEntries).Count | Should -BeGreaterThan 0
        @($Private:BodyEntries | Where-Object { -not $_.ShapeOnly }).Count | Should -Be 0
    }

    It "carries a log out of a failed run as well" {
        # Precisely when someone reads the log.
        $script:Failures["execute"] = "500 (Internal Server Error)"
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext)

        $Outcome.ErrorRecord | Should -Not -BeNullOrEmpty
        @($Outcome.Log | Where-Object { $_.Text -match "QueryUrl" }).Count | Should -BeGreaterThan 0
    }
}

Describe "Invoke-OmadaExecutePipeline - execute selection" {
    BeforeEach { Reset-PipelineTestState }

    It "creates a temporary object, executes against it, and deletes it" {
        # The full lifetime, in one assertion. The delete is the part that used to be easy to lose.
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *")

        Get-CallSequence | Should -Be @("get", "probe", "temp-post", "execute", "delete")
        $Outcome.TempQueryDoId | Should -Be 777
    }

    It "executes against the temporary object, not the saved query" {
        Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *") | Out-Null

        $Execute = $script:Calls | Where-Object { $_.Key -eq "execute" } | Select-Object -First 1
        $Execute.Body["dataTypeArgs"]["targetId"] | Should -Be 777
    }

    It "points each statement's temporary object at that statement's own connection" {
        # Issue #152 on top of #151: a statement that named its own database resolves to a connection
        # that is not the dropdown's, and each statement may differ. The per-statement upsert is the
        # only place that follows it.
        $Context = New-PipelineContext -QueryText "SELECT 2"
        $Context.Statements = @(
            [pscustomobject]@{ Ordinal = 1; Text = "SELECT 1"; DataConnectionDoId = "99" }
            [pscustomobject]@{ Ordinal = 2; Text = "SELECT 2"; DataConnectionDoId = "77" }
            [pscustomobject]@{ Ordinal = 3; Text = "SELECT 3"; DataConnectionDoId = $null }
        )

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        $Temp = @($script:Calls | Where-Object { $_.Key -in @("temp-put", "temp-post") })
        @($Temp).Count | Should -Be 3
        $Temp[0].Body["C_SQLTROUBLESHOOTING_DATACONNECTION"]["Id"] | Should -Be "99"
        $Temp[1].Body["C_SQLTROUBLESHOOTING_DATACONNECTION"]["Id"] | Should -Be "77"
        # No database of its own: falls back to the selected connection, as every statement did
        # before #152.
        $Temp[2].Body["C_SQLTROUBLESHOOTING_DATACONNECTION"]["Id"] | Should -Be "42"
    }

    It "leaves the user's own query object on the connection they chose" {
        # The save must keep writing Context.DataConnectionDoId, or executing a prefixed query would
        # silently move the saved query onto another connection (#152 criterion 7).
        $Context = New-PipelineContext -QueryText "SELECT 2"
        $Context.Statements = @([pscustomobject]@{ Ordinal = 1; Text = "SELECT 1"; DataConnectionDoId = "99" })

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        $Save = $script:Calls | Where-Object { $_.Key -eq "save" } | Select-Object -First 1
        $Save | Should -Not -BeNullOrEmpty
        $Save.Body["C_SQLTROUBLESHOOTING_DATACONNECTION"]["Id"] | Should -Be "42"
    }

    It "creates the temporary object for ONE prefixed statement with no selection" {
        # The case the old NeedTempObject test missed: Count is 1 and SelectionText is empty, so
        # without the DataConnectionDoId condition this would execute the SAVED query - which is
        # attached to the dropdown's connection - and the statement would silently run against the
        # wrong database, which is the whole point of #152.
        $Context = New-PipelineContext
        $Context.Statements = @([pscustomobject]@{ Ordinal = 1; Text = "SELECT 1"; DataConnectionDoId = "99" })

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        # temp-post, not temp-put: the probe finds nothing in this state, so the object is created
        # rather than updated. Asserting either keeps the test about "a temporary object was used"
        # instead of about which verb that happened to take.
        @($script:Calls | Where-Object { $_.Key -in @("temp-put", "temp-post") }).Count | Should -Be 1
        $Execute = $script:Calls | Where-Object { $_.Key -eq "execute" } | Select-Object -First 1
        $Execute.Body["dataTypeArgs"]["targetId"] | Should -Be 777
    }

    It "creates no temporary object for ONE unprefixed statement with no selection" {
        # The other half of the same rule: nothing about #152 may add a round trip to a query that
        # names no database (criterion 14).
        $Context = New-PipelineContext
        $Context.Statements = @([pscustomobject]@{ Ordinal = 1; Text = "SELECT 1"; DataConnectionDoId = $null })

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        Get-CallSequence | Should -Be @("get", "execute")
    }

    It "undeletes and reuses a soft-deleted temporary object rather than creating another" {
        # Without this the shared TMP_<InstanceGuid> object would be recreated on every run and stale
        # ones would pile up on the tenant.
        $script:Responses["probe"] = [pscustomobject]@{ Value = @([pscustomobject]@{ Id = 777; Deleted = $true }) }

        Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *") | Out-Null

        Get-CallSequence | Should -Be @("get", "probe", "undelete", "temp-put", "execute", "delete")
    }

    It "reuses an existing, not-deleted temporary object without undeleting it" {
        $script:Responses["probe"] = [pscustomobject]@{ Value = @([pscustomobject]@{ Id = 777; Deleted = $false }) }

        Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *") | Out-Null

        Get-CallSequence | Should -Be @("get", "probe", "temp-put", "execute", "delete")
    }

    It "falls back to the reused id when the PUT answers without one" {
        # A PUT onto a recovered object returns no Id, but it is still the object the query has to
        # run against.
        $script:Responses["probe"] = [pscustomobject]@{ Value = @([pscustomobject]@{ Id = 777; Deleted = $false }) }
        $script:Responses["temp-put"] = [pscustomobject]@{ }

        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *")

        $Outcome.TempQueryDoId | Should -Be 777
    }

    It "carries on to create a new object when the probe itself fails" {
        # Non-fatal, exactly as it is on the UI thread: a failed probe means "assume there is none".
        $script:Failures["probe"] = "probe blew up"

        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *")

        Get-CallSequence | Should -Be @("get", "probe", "temp-post", "execute", "delete")
        $Outcome.ErrorRecord | Should -BeNullOrEmpty
    }

    It "publishes the temporary object's id WHILE it is still running" {
        # The only way the UI thread can clean up after a CANCELLED run: stopping the pipeline kills
        # its own finally, so the id has to escape the worker before the worker finishes.
        #
        # Observed mid-flight rather than afterwards, and that distinction is the point: by the time
        # the pipeline returns normally it has already deleted the object and cleared the id again,
        # so an assertion at the end would say nothing about what a cancellation could have seen.
        $Progress = [hashtable]::Synchronized(@{})
        $Context = New-PipelineContext -SelectionText "SELECT TOP 1 *"
        $Context.Progress = $Progress

        $script:ObservedDuringExecute = "not reached"
        function Invoke-OmadaRequestCore {
            param([hashtable]$Parameters)
            $Key = Get-CallKey -Method $Parameters.Method -Uri $Parameters.Uri -Body $Parameters.Body
            $script:Calls.Add([pscustomobject]@{ Key = $Key; Method = $Parameters.Method; Uri = $Parameters.Uri; Body = $Parameters.Body })
            if ($Key -eq "execute") {
                $script:ObservedDuringExecute = $Progress.TempQueryDoId
            }
            if ($script:Responses.ContainsKey($Key)) { return @{ Result = $script:Responses[$Key]; ErrorRecord = $null } }
            return @{ Result = $null; ErrorRecord = $null }
        }

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        $script:ObservedDuringExecute | Should -Be 777
        # And cleared once the pipeline has deleted it itself, so a cancellation racing the finish
        # does not delete it a second time.
        $Progress.TempQueryDoId | Should -BeNullOrEmpty
    }
}

Describe "Invoke-OmadaExecutePipeline - failures" {
    BeforeEach { Reset-PipelineTestState }

    It "stops at the failing step and says which one it was" {
        $script:Failures["save"] = "save rejected"

        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -QueryText "SELECT 2")

        $Outcome.FailedStep | Should -Be "SaveQuery"
        $Outcome.ErrorRecord.Exception.Message | Should -Be "save rejected"
        Get-CallSequence | Should -Not -Contain "execute"
    }

    It "does not execute when the query could not be fetched" {
        $script:Failures["get"] = "not found"

        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext)

        $Outcome.FailedStep | Should -Be "GetQueryObject"
        Get-CallSequence | Should -Be @("get")
    }

    It "deletes the temporary object even when the execute fails" {
        # The leak that matters: the object exists on the tenant by then, and a failed query is
        # exactly when it would be easiest to forget.
        $script:Failures["execute"] = "server error"

        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *")

        Get-CallSequence | Should -Contain "delete"
        $Outcome.FailedStep | Should -Be "ExecuteQuery"
    }

    It "does not let a failing clean-up mask the real error" {
        $script:Failures["execute"] = "server error"
        $script:Failures["delete"] = "delete blew up"

        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *")

        $Outcome.ErrorRecord.Exception.Message | Should -Be "server error"
    }

    It "stops when the temporary object could not be created" {
        $script:Failures["temp-post"] = "create rejected"

        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext -SelectionText "SELECT TOP 1 *")

        $Outcome.FailedStep | Should -Be "TempQueryUpsert"
        Get-CallSequence | Should -Not -Contain "execute"
    }
}

Describe "Invoke-OmadaExecutePipeline - one query per statement (#151)" {
    BeforeEach { Reset-PipelineTestState }

    function script:New-TestStatement {
        # The shape Get-SqlScriptStatement hands the pipeline: an ordinal and the statement's own
        # source text.
        param([string[]]$Text)

        $Private:Ordinal = 0
        return @($Text | ForEach-Object {
                $Private:Ordinal++
                [PSCustomObject]@{ Ordinal = $Private:Ordinal; Text = $_ }
            })
    }

    function script:Get-TempQueryText {
        # The SQL each upsert put on the temporary object, in the order the upserts happened. This is
        # what proves each statement ran as ITSELF rather than all of them running the same text.
        return @($script:Calls |
                Where-Object { $_.Key -eq "temp-post" -or $_.Key -eq "temp-put" } |
                ForEach-Object { $_.Body["C_QUERY"] })
    }

    It "executes every statement, in editor order, on the one temporary object" {
        # The acceptance criterion: a script with two SELECTs executed with nothing selected produces
        # two executes. One probe and one delete bracket the whole run; the upsert is what repeats,
        # because only the temporary object's CONTENT changes per statement.
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2")

        $Outcome = Invoke-OmadaExecutePipeline -Context $Context

        Get-CallSequence | Should -Be @("get", "probe", "temp-post", "execute", "temp-put", "execute", "delete")
        @($Outcome.StatementOutcome).Count | Should -Be 2
        @($Outcome.StatementOutcome | ForEach-Object { $_.Ordinal }) | Should -Be @(1, 2)
    }

    It "sends each statement's own SQL to the temporary object" {
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2", "SELECT 3")

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        Get-TempQueryText | Should -Be @("SELECT 1", "SELECT 2", "SELECT 3")
    }

    It "fetches and saves once for the whole run rather than once per statement" {
        # Each statement is its own query, but they all belong to one execute of one saved query.
        # Saving per statement would write the editor's text to the tenant N times.
        $Context = New-PipelineContext -QueryText "SELECT 2"
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2")

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        @($script:Calls | Where-Object { $_.Key -eq "get" }).Count | Should -Be 1
        @($script:Calls | Where-Object { $_.Key -eq "save" }).Count | Should -Be 1
    }

    It "probes for the temporary object once, however many statements run" {
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2", "SELECT 3", "SELECT 4")

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        @($script:Calls | Where-Object { $_.Key -eq "probe" }).Count | Should -Be 1
        @($script:Calls | Where-Object { $_.Key -eq "execute" }).Count | Should -Be 4
    }

    It "deletes the temporary object once, after the last statement" {
        # Deleting per statement would destroy the object the next statement is about to upsert onto.
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2")

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        @($script:Calls | Where-Object { $_.Key -eq "delete" }).Count | Should -Be 1
        (Get-CallSequence)[-1] | Should -Be "delete"
    }

    It "creates no temporary object at all for a single statement with no selection" {
        # The guarantee that a single execute stays identical to what it was before this issue: it
        # runs the saved query directly, exactly as it always did.
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1")

        $Outcome = Invoke-OmadaExecutePipeline -Context $Context

        Get-CallSequence | Should -Be @("get", "execute")
        $Outcome.TempQueryDoId | Should -BeNullOrEmpty

        $Execute = $script:Calls | Where-Object { $_.Key -eq "execute" } | Select-Object -First 1
        $Execute.Body["dataTypeArgs"]["targetId"] | Should -Be 100
    }

    It "still uses the temporary object for a single statement when there is a selection" {
        # Selecting one statement and executing is one result, through the temporary object, as before.
        $Context = New-PipelineContext -SelectionText "SELECT TOP 1 *"
        $Context.Statements = New-TestStatement -Text @("SELECT TOP 1 *")

        $Outcome = Invoke-OmadaExecutePipeline -Context $Context

        Get-CallSequence | Should -Be @("get", "probe", "temp-post", "execute", "delete")
        $Outcome.TempQueryDoId | Should -Be 777
    }

    It "runs the statements it was given rather than the selection as a whole" {
        # Selecting two of three statements runs those two, each as its own query - not the selected
        # text in one go.
        $Context = New-PipelineContext -SelectionText "SELECT 1;`r`nSELECT 2;"
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2")

        Invoke-OmadaExecutePipeline -Context $Context | Out-Null

        @($script:Calls | Where-Object { $_.Key -eq "execute" }).Count | Should -Be 2
        Get-TempQueryText | Should -Be @("SELECT 1", "SELECT 2")
    }

    It "reports the first statement's outcome as the run's outcome" {
        # Everything that consumed this outcome before #151 reads QueryResult/ErrorRecord/FailedStep,
        # and a single-statement execute must keep reporting exactly what it used to. A later
        # statement must not overwrite them.
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2")

        $Outcome = Invoke-OmadaExecutePipeline -Context $Context

        $Outcome.QueryResult.d.Records | Should -Be 2
        $Outcome.ErrorRecord | Should -BeNullOrEmpty
        $Outcome.FailedStep | Should -BeNullOrEmpty
    }

    It "continues past a failing statement and records the failure against that statement" {
        # SSMS behaviour, and the decision this issue was delivered with: one statement failing does
        # not abandon the ones after it. $script:Failures keys by logical request, which would fail
        # every execute, so only the SECOND execute is failed here - which is the whole point.
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2", "SELECT 3")

        $Private:Original = ${function:Invoke-OmadaRequestCore}
        try {
            $script:ExecuteCount = 0
            function Invoke-OmadaRequestCore {
                param([hashtable]$Parameters)
                $Key = Get-CallKey -Method $Parameters.Method -Uri $Parameters.Uri -Body $Parameters.Body
                $script:Calls.Add([pscustomobject]@{ Key = $Key; Method = $Parameters.Method; Uri = $Parameters.Uri; Body = $Parameters.Body })

                if ($Key -eq "execute") {
                    $script:ExecuteCount++
                    if ($script:ExecuteCount -eq 2) {
                        return @{ Result = $null; ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                                [System.Exception]::new("statement 2 failed"), "PipelineTestFailure",
                                [System.Management.Automation.ErrorCategory]::ConnectionError, $null) }
                    }
                }

                if ($script:Responses.ContainsKey($Key)) { return @{ Result = $script:Responses[$Key]; ErrorRecord = $null } }
                return @{ Result = $null; ErrorRecord = $null }
            }

            $Outcome = Invoke-OmadaExecutePipeline -Context $Context

            # All three were attempted, and the third ran AFTER the failure rather than being skipped.
            $script:ExecuteCount | Should -Be 3
            @($Outcome.StatementOutcome).Count | Should -Be 3

            $Outcome.StatementOutcome[0].ErrorRecord | Should -BeNullOrEmpty
            $Outcome.StatementOutcome[1].ErrorRecord.Exception.Message | Should -Be "statement 2 failed"
            $Outcome.StatementOutcome[1].FailedStep | Should -Be "ExecuteQuery"
            $Outcome.StatementOutcome[2].ErrorRecord | Should -BeNullOrEmpty

            # And the temporary object is still cleaned up after a run that contained a failure.
            Get-CallSequence | Should -Contain "delete"
        }
        finally {
            # Restored, so a redefined transport cannot leak into the Describe blocks after this one.
            Set-Item -Path "function:Invoke-OmadaRequestCore" -Value $Private:Original
        }
    }

    It "keeps a statement's own text on its outcome, for the Results header and the Messages summary" {
        $Context = New-PipelineContext
        $Context.Statements = New-TestStatement -Text @("SELECT 1", "SELECT 2")

        $Outcome = Invoke-OmadaExecutePipeline -Context $Context

        @($Outcome.StatementOutcome | ForEach-Object { $_.Text }) | Should -Be @("SELECT 1", "SELECT 2")
    }

    It "executes exactly once when the caller passes no statements at all" {
        # Backward compatibility, and it is what every test above this block relies on: the inline
        # fallback path does not split anything, and must keep getting one execute of one query.
        $Outcome = Invoke-OmadaExecutePipeline -Context (New-PipelineContext)

        Get-CallSequence | Should -Be @("get", "execute")
        @($Outcome.StatementOutcome).Count | Should -Be 1
    }
}

Describe "Invoke-OmadaExecutePipeline is runspace-safe" {
    It "runs in a bare runspace with none of this module's state or functions" {
        # The property the whole design rests on. A $Script: read or a Write-LogOutput added here
        # later would break every background execute with a CommandNotFoundException that no
        # ordinary unit test would catch, because in the test process those names resolve fine.
        $Shell = [powershell]::Create()
        try {
            [void]$Shell.AddScript({
                    param($PrivatePath)
                    . (Join-Path $PrivatePath "New-OmadaQueryRequest.ps1")
                    . (Join-Path $PrivatePath "Invoke-OmadaExecutePipeline.ps1")
                    function Invoke-OmadaRequestCore {
                        param([hashtable]$Parameters)
                        if ($Parameters.Uri -like "*GetPagingData*") {
                            return @{ Result = [pscustomobject]@{ d = [pscustomobject]@{ Records = 1 } }; ErrorRecord = $null }
                        }
                        return @{ Result = [pscustomobject]@{ Id = 100; C_QUERY = "SELECT 1" }; ErrorRecord = $null }
                    }
                    $Outcome = Invoke-OmadaExecutePipeline -Context @{
                        BaseUrl = "https://tenant.omada.cloud"; QueryDoId = 100
                        QueryText = "SELECT 1"; CurrentQueryText = "SELECT 1"
                        DisplayName = "Q"; CurrentDisplayName = "Q"
                        SelectionText = $null; TempName = "TMP_abc"; SkipSave = $false
                        Parameters = @{ SessionKey = "pool" }
                    }
                    return $Outcome.QueryResult.d.Records
                }).AddArgument((Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private"))

            $Output = $Shell.Invoke()

            $Shell.Streams.Error | Should -BeNullOrEmpty
            $Output[0] | Should -Be 1
        }
        finally {
            $Shell.Dispose()
        }
    }
}
