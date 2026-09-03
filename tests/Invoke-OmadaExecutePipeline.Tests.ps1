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
