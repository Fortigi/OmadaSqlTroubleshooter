# The label a schema request carries on the completion queue. A constant because it is matched, not
# just displayed: Get-SqlSchemaObject reads the queue through it to decide whether a fetch for the
# same pool and database is already outstanding.
$Script:SqlSchemaRequestDescription = "SQL schema"

function Get-SqlSchemaObject {
    <#
    .SYNOPSIS
    Retrieves a data connection's SQL schema, caches it per connection pool, and feeds it to the
    schema window and the editor's IntelliSense.

    .DESCRIPTION
    Called with no parameters it does exactly what it has always done: fetch the ACTIVE tab's data
    connection. Issue #158 added the two parameters so the same path can fetch any other data
    connection, which is what the schema window's database nodes and the editor's cross-database
    completion both need. Everything that makes the active fetch safe - the connection guard, the
    per-pool cache, the in-flight check, the background dispatch and the UI-thread retry - therefore
    applies unchanged to a non-active one, rather than being reimplemented beside it.

    .PARAMETER DataConnectionDoId
    The data connection to fetch. Omitted means the active tab's connection.

    .PARAMETER DataConnectionName
    That connection's display name, used for logging and for the setSchemaForDatabase push, which
    addresses a database by name because that is what the user writes in the query. Omitted for the
    active connection, whose name is taken from $Script:AppConfig.CurrentDataConnection.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DataConnectionDoId,

        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DataConnectionName
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip reconnect" | Write-LogOutput -LogType DEBUG
            return
        }

        # Retrieving the schema is an authenticated round-trip, so it may only run for a tab that
        # genuinely connected. $Script:ConnectionStatus is the active tab's own connection flag
        # (Set-ActiveTabContext swaps it in and out per tab, Set-SqlConnectionState is its only
        # writer), which is the state this guard must read. The checks below are not a substitute:
        # $Script:RunTimeConfig.ReconnectStatus is process-global and is already 3 once any tab's
        # editor has loaded, Test-ConnectionRequirements only verifies that a URL and an
        # authentication option are filled in, and CurrentDataConnection.DoId is restored from
        # config - a restored, deliberately disconnected tab satisfies all three. Without this the
        # NavigationCompleted handler in Initialize-WebViewForTab.ps1 silently authenticated against
        # the tenant, defeating -NoReconnect and a declined reconnect prompt alike.
        if (-not $Script:ConnectionStatus) {
            "Tab is not connected; skipping SQL schema retrieval." | Write-LogOutput -LogType DEBUG
            return
        }

        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        # The active connection is the default target, so every pre-#158 caller behaves exactly as
        # before. A caller that names a DoId gets that one instead - and $IsActiveDatabase decides
        # what the completion is allowed to touch: only the active database owns the window title,
        # the editor's primary setSchema model and the validation re-trigger.
        $Private:TargetDoId = if ($PSBoundParameters.ContainsKey("DataConnectionDoId") -and ![string]::IsNullOrWhiteSpace($DataConnectionDoId)) {
            $DataConnectionDoId
        }
        else {
            [string]$Script:AppConfig.CurrentDataConnection.DoId
        }

        $Private:IsActiveDatabase = ($Private:TargetDoId -eq [string]$Script:AppConfig.CurrentDataConnection.DoId)

        $Private:TargetName = if ($Private:IsActiveDatabase) {
            [string]$Script:AppConfig.CurrentDataConnection.FullName
        }
        elseif (![string]::IsNullOrWhiteSpace($DataConnectionName)) {
            $DataConnectionName
        }
        else {
            $Private:TargetDoId
        }

        # NOT a positive-integer check, and that was tried and reverted (issue #165) - the comment is
        # here so it is not tried again.
        #
        # The problem it was reaching for is real: a DoId of 0 names no database, and the schema
        # preload was asking the tenant for it, which an E2E refresh caught as a third fetch (ids
        # 0,42,43) for a pool holding two databases. Tightening THIS gate to "parse as a positive
        # integer" does stop that - and also stops a legitimate fetch.
        #
        # NoReconnectStartup :: "accepting the reconnect prompt still connects the tab and retrieves
        # its schema" failed immediately, with the message its author wrote for exactly this mistake:
        # "the guard must not block the connect path". A restored tab accepting reconnect does not have
        # a positive-integer DoId at the moment this runs, so the stricter gate turned a wasted request
        # into a MISSING one - strictly worse, and invisible except as a schema that never loaded.
        #
        # The junk DoId comes from the dropdown, so it is filtered where the dropdown is enumerated:
        # Start-SqlSchemaPreload skips an entry whose DoId is not a positive integer, and
        # Get-DataConnectionReferenceList skips a nameless entry before that. This gate stays as it
        # was - a caller that genuinely has no DoId falls into the "DoID is not set" branch below.
        if (![string]::IsNullOrWhiteSpace($Private:TargetDoId)) {
            "Retrieve current SqlSchema for data connection DoId: {0}" -f $Private:TargetDoId | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/webservice/SyntaxHighlighting.asmx/GetSqlSchema" -f $Script:AppConfig.BaseUrl
            "SqlSchemaUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Retrieve schema {0}" -f $Private:TargetName | Write-LogOutput

            # Share the schema across tabs that belong to the same connection pool (SessionKey) and
            # target the same data connection (DoId): same tenant + same database => identical
            # schema, so the first tab to fetch it populates a session-lifetime cache and every
            # other matching connected tab reuses it without another round-trip.
            $SchemaCacheKey = Get-SqlSchemaCacheKey -DataConnectionDoId $Private:TargetDoId
            if ($null -eq $Script:SqlSchemaCache) {
                $Script:SqlSchemaCache = @{}
            }

            if ($Script:SqlSchemaCache.ContainsKey($SchemaCacheKey)) {
                # Issue #158 criterion 5: a database already in the per-pool cache costs no request.
                # It still runs the completion, because the CALLER has not been served yet - the tree
                # node is empty and the editor has no model for this database until it does.
                "Using cached SQL schema for '{0}'" -f $SchemaCacheKey | Write-LogOutput -LogType DEBUG
                Complete-SqlSchemaRetrieval -SchemaResponse $Script:SqlSchemaCache[$SchemaCacheKey] -SchemaCacheKey $SchemaCacheKey `
                    -DataConnectionDoId $Private:TargetDoId -DataConnectionName $Private:TargetName -IsActiveDatabase:$Private:IsActiveDatabase
                return
            }

            # The cache alone stopped being enough once this fetch went off-thread (issue #40): the
            # cache is only populated when the response LANDS, so two calls close together - a
            # connect immediately followed by a data-connection change, say - would both miss it and
            # both hit the tenant. This preserves the once-per-pool-per-database contract the cache
            # was written for.
            #
            # Read straight off the completion queue rather than kept in a side table of "keys in
            # flight". A side table has to be cleared on every path a request can leave by - success,
            # failure, and abandonment when its tab is closed - and a key left behind on the
            # abandonment path would block that pool and database from ever fetching its schema again
            # for the rest of the session. The queue cannot get out of step with itself.
            # Any matching item on the queue counts, including one whose worker has already finished
            # but which the poll timer has not drained yet. Its completion is queued and about to
            # populate the cache and push the schema to the editor, so the caller's intent is already
            # being served - dispatching again in that window would be a duplicate request for
            # exactly the answer that is moments away.
            if (@($Script:PendingWebViewCompletions | Where-Object {
                        $_.Description -eq $Script:SqlSchemaRequestDescription -and
                        $_.Context.Caller.SchemaCacheKey -eq $SchemaCacheKey
                    }).Count -gt 0) {
                "SQL schema for '{0}' is already being retrieved; not requesting it twice." -f $SchemaCacheKey | Write-LogOutput -LogType DEBUG
                return
            }

            $Script:RunTimeData.RestMethodParam.Body = @{
                connectionId = $Private:TargetDoId
            }
            $Script:RunTimeData.RestMethodParam.Method = "POST"

            # Issue #40's first background caller, and deliberately the least risky one: the schema
            # fetch is already cached, already tolerant of failure, binds no grid and creates no
            # temporary object on the tenant - so it proves the machinery without putting a query
            # result at stake. It is also the round-trip that freezes the window on connect.
            #
            # The completion block is plain (never .GetNewClosure()), so it reads the cache key from
            # $Pending.Context.Caller instead of re-deriving it: by the time it runs, the user may
            # have switched to a tab with a different SessionKey or data connection, and the key must
            # be the one this request was issued for.
            # The request itself travels on the context, not just the cache key. A retry cannot simply
            # re-use $Script:RunTimeData.RestMethodParam: that hashtable is overwritten by whatever
            # request the tab makes next, so by the time this completion runs it may describe an
            # entirely different call. (That staleness is visible in the logs - the dispatch of an
            # execute records the schema request's URI, because nothing had overwritten it yet.)
            # The target database travels on the context for the same reason the cache key does: by
            # the time this completion runs the user may have switched tab or data connection, so
            # "which database is this a response for" cannot be re-derived from the active tab.
            # A pipeline rather than a single request: the worker also builds the editor's JSON and the
            # validation index from the response (Invoke-OmadaSqlSchemaPipeline), which used to be done
            # on the UI thread when it landed - about two seconds per connect on a cloud PC.
            $Private:Pending = Invoke-OmadaPSWebRequestWrapperAsync -Description $Script:SqlSchemaRequestDescription -Context @{
                SchemaCacheKey      = $SchemaCacheKey
                DataConnectionDoId  = $Private:TargetDoId
                DataConnectionName  = $Private:TargetName
                IsActiveDatabase    = $Private:IsActiveDatabase
                Uri                 = $Script:RunTimeData.RestMethodParam.Uri
                Method              = $Script:RunTimeData.RestMethodParam.Method
                Body                = $Script:RunTimeData.RestMethodParam.Body
            } -PipelineContext @{
                PipelineFunction = "Invoke-OmadaSqlSchemaPipeline"
                PipelineFiles    = $Script:OmadaWorkerChainFile["Invoke-OmadaSqlSchemaPipeline"]
            } -OnResultScriptBlock {
                param($Pending)

                # What the worker sent back: the pipeline's outcome, whose log is replayed here and
                # whose derived values are handed on, or - on a path that ran a plain request - the
                # response itself. Either way the rest of this block sees just the response.
                $Private:Unwrapped = ConvertFrom-SqlSchemaPipelineOutcome -Outcome $Pending.Outcome
                $Pending | Add-Member -NotePropertyName "Outcome" -NotePropertyValue $Private:Unwrapped.Response -Force
                # A worker that could not run the request at all is not an answer. Retry once on the
                # UI thread, where authentication works - the same fallback the execute path takes,
                # and for the same reason: a fresh worker runspace cannot always establish an
                # OmadaWeb.PS session.
                #
                # Safe to retry whatever the cause: GetSqlSchema is POST-shaped but purely a read, so
                # running it twice changes nothing on the tenant. (The execute path needs a far more
                # careful gate for exactly this reason - see CompletedSteps there.)
                #
                # Not retried for a tab that is no longer connected: Resolve-OmadaRequestFailure tears
                # the tab down for the two tenant-level failures before throwing, and those are the
                # tenant's answer rather than a worker that could not do its job.
                if (($null -eq $Pending.Outcome -or $Pending.Outcome -is [System.Management.Automation.ErrorRecord]) -and $Script:ConnectionStatus) {
                    $Private:Reason = if ($null -eq $Pending.Outcome) { "the background worker returned no result" } else { $Pending.Outcome.Exception.Message }
                    "The SQL schema could not be retrieved on a background worker: {0}" -f $Private:Reason | Write-LogOutput -LogType DEBUG
                    Disable-OmadaBackgroundRequest -Reason $Private:Reason

                    # Method carried alongside Uri and Body rather than hard-coded, so the retry
                    # cannot drift from the request that was actually dispatched.
                    "Retrying the SQL schema retrieval on the UI thread." | Write-LogOutput -LogType DEBUG
                    $Script:RunTimeData.RestMethodParam.Uri = $Pending.Context.Caller.Uri
                    $Script:RunTimeData.RestMethodParam.Method = $Pending.Context.Caller.Method
                    $Script:RunTimeData.RestMethodParam.Body = $Pending.Context.Caller.Body
                    Complete-SqlSchemaRetrieval -SchemaResponse (Invoke-OmadaPSWebRequestWrapper) -SchemaCacheKey $Pending.Context.Caller.SchemaCacheKey `
                        -DataConnectionDoId $Pending.Context.Caller.DataConnectionDoId -DataConnectionName $Pending.Context.Caller.DataConnectionName `
                        -IsActiveDatabase:([bool]$Pending.Context.Caller.IsActiveDatabase)
                    return
                }
                Complete-SqlSchemaRetrieval -SchemaResponse $Pending.Outcome -SchemaCacheKey $Pending.Context.Caller.SchemaCacheKey `
                    -DataConnectionDoId $Pending.Context.Caller.DataConnectionDoId -DataConnectionName $Pending.Context.Caller.DataConnectionName `
                    -IsActiveDatabase:([bool]$Pending.Context.Caller.IsActiveDatabase) `
                    -EditorJson $Private:Unwrapped.EditorJson -SchemaModel $Private:Unwrapped.SchemaModel
            }

            if ($null -ne $Private:Pending) {
                # Dispatched. Everything after the response now happens in the completion block, and
                # the item's presence on the queue is itself the "already in flight" record.
                return
            }

            # Not eligible for a worker, or none available: exactly the pre-#40 behaviour.
            $ReturnValue = Invoke-OmadaPSWebRequestWrapper
            Complete-SqlSchemaRetrieval -SchemaResponse $ReturnValue -SchemaCacheKey $SchemaCacheKey `
                -DataConnectionDoId $Private:TargetDoId -DataConnectionName $Private:TargetName -IsActiveDatabase:$Private:IsActiveDatabase
        }
        else {
            "SqlSchema DoID is not set! Cannot retrieve Sql schema!" | Write-LogOutput -LogType WARNING -SkipDialog
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function ConvertFrom-SqlSchemaPipelineOutcome {
    <#
    .SYNOPSIS
    The schema response a background completion received, with whatever the worker built from it.

    .DESCRIPTION
    A schema request now normally runs as Invoke-OmadaSqlSchemaPipeline, whose outcome carries the
    response together with the editor JSON, the validation index and a log. Not every path delivers
    that shape: a request that could not be classified, a test double, or anything handing over a
    plain response. This turns either into the same three values, so the completion never has to know
    which path it came from - and replays the pipeline's log, which the worker could not write itself.

    .PARAMETER Outcome
    $Pending.Outcome: a pipeline outcome, a response, an ErrorRecord, or $null.

    .OUTPUTS
    Hashtable @{ Response; EditorJson; SchemaModel }. Response is the ErrorRecord when the request
    failed, which is what every check after this one tests for.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Outcome
    )

    # No tracer preamble: the outcome is the tenant's schema.

    if ($Outcome -is [System.Collections.IDictionary] -and $true -eq $Outcome["IsSqlSchemaPipeline"]) {
        Write-ExecutePipelineLog -Log $Outcome["Log"]

        return @{
            Response    = if ($null -ne $Outcome["ErrorRecord"]) { $Outcome["ErrorRecord"] } else { $Outcome["Result"] }
            EditorJson  = $Outcome["EditorJson"]
            SchemaModel = $Outcome["SchemaModel"]
        }
    }

    return @{
        Response    = $Outcome
        EditorJson  = $null
        SchemaModel = $null
    }
}

function Complete-SqlSchemaRetrieval {
    <#
    .SYNOPSIS
    Everything that happens once a SQL schema response is in hand: cache it, rebuild the schema
    window's tree, and push the schema to the Monaco editor for IntelliSense.

    .DESCRIPTION
    Split out of Get-SqlSchemaObject by issue #40 so the same work runs whether the response arrived
    synchronously or from a background worker. It touches WPF elements and the editor, so it is UI
    thread only - which it always is: the background path reaches it from the completion poll timer,
    with the owning tab already made active by Set-ActiveTabContext.

    .PARAMETER SchemaResponse
    What the request produced: the response object, an ErrorRecord, or $null.

    .PARAMETER SchemaCacheKey
    The "<SessionKey>|<DataConnectionDoId>" key this response was fetched for. Passed in rather than
    re-derived, because the active tab may have changed since the request was issued.

    .PARAMETER DataConnectionDoId
    The data connection this response describes. Used to find its node on the schema tree.

    .PARAMETER DataConnectionName
    That connection's name, which is how setSchemaForDatabase addresses a database - the user writes
    the name in the query, not the DoId.

    .PARAMETER IsActiveDatabase
    Whether this response is for the tab's CURRENT data connection. Only the active database owns the
    window title, the editor's primary setSchema model and the validation re-trigger; a response for
    any other database (issue #158) populates its own tree node and its own per-database editor model
    and touches nothing else. Omitted means active, so every pre-#158 caller is unaffected.

    .PARAMETER EditorJson
    The editor's JSON for this response, when the background worker already built it
    (Invoke-OmadaSqlSchemaPipeline). Stored as the memoised JSON, so it is not built again here.

    .PARAMETER SchemaModel
    The validation index for this response, when the background worker already built it. Stored as the
    memoised index, so the validation pass does not build it on the UI thread.
    #>
    [CmdLetBinding()]
    param(
        $SchemaResponse,

        [Parameter(Mandatory = $true)]
        [string]$SchemaCacheKey,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DataConnectionDoId,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DataConnectionName,

        [Parameter(Mandatory = $false)]
        [switch]$IsActiveDatabase,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$EditorJson,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $SchemaModel
    )
    try {
        # Unbound means active. The switch would otherwise default to $false and silently demote
        # every caller that predates issue #158 to the non-active path.
        $Private:Active = if ($PSBoundParameters.ContainsKey("IsActiveDatabase")) { [bool]$IsActiveDatabase } else { $true }

        $Private:DisplayName = if (![string]::IsNullOrWhiteSpace($DataConnectionName)) {
            $DataConnectionName
        }
        else {
            [string]$Script:AppConfig.CurrentDataConnection.FullName
        }

        $ReturnValue = $SchemaResponse

        if ($null -ne $ReturnValue -and $ReturnValue -isnot [System.Management.Automation.ErrorRecord] -and $null -ne $ReturnValue.d) {
            if ($null -eq $Script:SqlSchemaCache) {
                $Script:SqlSchemaCache = @{}
            }

            # A cache hit hands back the very object that is already cached (Get-SqlSchemaObject), and
            # nothing derived from it can be stale - so nothing is dropped. Dropping it anyway made
            # every tab switch, window open and node expand rebuild the validation index and the
            # editor JSON for a response that had not changed: half a second and a second, per large
            # database, on the UI thread.
            $Private:IsSameResponse = $Script:SqlSchemaCache.ContainsKey($SchemaCacheKey) -and [object]::ReferenceEquals($Script:SqlSchemaCache[$SchemaCacheKey], $ReturnValue)

            if (-not $Private:IsSameResponse) {
                $Script:SqlSchemaCache[$SchemaCacheKey] = $ReturnValue

                # The index the schema validation pass resolves against, and the editor's JSON, are
                # built from this response and memoised beside it. Dropping them for a NEW response is
                # what stops either outliving the response it was built from - after a refresh, the
                # pass would otherwise keep answering from the schema the user just asked to replace.
                foreach ($Private:DerivedCache in @($Script:SqlSchemaModelCache, $Script:SqlSchemaEditorJsonCache)) {
                    if ($null -ne $Private:DerivedCache) {
                        $Private:DerivedCache.Remove($SchemaCacheKey)
                    }
                }
            }

            # What the background worker built from THIS response, so the UI thread does not build it
            # again. Stored after the drop above: it belongs to the response just stored.
            if (![string]::IsNullOrWhiteSpace($EditorJson)) {
                if ($null -eq $Script:SqlSchemaEditorJsonCache) {
                    $Script:SqlSchemaEditorJsonCache = @{}
                }
                $Script:SqlSchemaEditorJsonCache[$SchemaCacheKey] = $EditorJson
            }

            if ($null -ne $SchemaModel) {
                if ($null -eq $Script:SqlSchemaModelCache) {
                    $Script:SqlSchemaModelCache = @{}
                }
                $Script:SqlSchemaModelCache[$SchemaCacheKey] = $SchemaModel
            }
        }

        if ($null -eq $ReturnValue -or $ReturnValue -is [System.Management.Automation.ErrorRecord] -or $null -eq $ReturnValue.d) {
            "No SQL schema returned for data connection '{0}'." -f $Private:DisplayName | Write-LogOutput -LogType WARNING -SkipDialog

            # Let the node be asked again. Without this a database whose first fetch failed would
            # stay marked "requested" for the rest of the session, so collapsing and re-expanding it
            # - the obvious thing to try - would do nothing at all.
            $Private:FailedNode = Get-SqlSchemaDatabaseNode -DataConnectionDoId $DataConnectionDoId
            if ($null -ne $Private:FailedNode -and $null -ne $Private:FailedNode.Tag -and -not $Private:FailedNode.Tag.Loaded) {
                $Private:FailedNode.Tag.Requested = $false
            }

            return $null
        }

        # The schema window is optional: this function also feeds the editor's IntelliSense, which
        # must work whether or not the user ever opens the SQL schema view. Only touch the window's
        # title/TreeView when they actually exist (they are created by Open-SqlSchemaForm) - the
        # setSchema push below always runs.
        $UpdateSchemaWindow = ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Definition -and $null -ne $Script:TreeViewSqlSchema)

        if ($UpdateSchemaWindow -and $Private:Active) {
            $Script:SqlSchemaForm.Definition.Title = "Sql Schema - {0}" -f $Private:DisplayName
        }

        "Retrieved object {0}" -f $Script:RunTimeData.SqlQueryObject | Write-LogOutput -LogType VERBOSE

        if ($UpdateSchemaWindow) {
            # Reconcile the database level first. It is idempotent and keeps the children of any
            # database that is already loaded, so this is safe to call on every response - including
            # the very first one, where the window opened before the connection list was read.
            Update-SqlSchemaDatabaseTree

            $Private:DatabaseNode = Get-SqlSchemaDatabaseNode -DataConnectionDoId $DataConnectionDoId
            if ($null -ne $Private:DatabaseNode) {
                $Private:TableCount = Add-SqlSchemaTreeNode -Parent $Private:DatabaseNode -SchemaResponse $ReturnValue
                if ($null -ne $Private:DatabaseNode.Tag) {
                    $Private:DatabaseNode.Tag.Loaded = $true
                }

                "Schema tree for '{0}': {1} table(s)" -f $Private:DisplayName, $Private:TableCount | Write-LogOutput -LogType DEBUG
            }
            else {
                # No node for this DoId: the connection is not in the dropdown (it was removed, or
                # the list has not been read yet). Nothing to populate, and nothing worth telling the
                # user - the editor still gets its model below.
                "No schema tree node for data connection DoId '{0}'; tree not updated." -f $DataConnectionDoId | Write-LogOutput -LogType DEBUG
            }

            # Every other database whose schema is already cached is filled too. The preload usually
            # lands before the window is opened, and its schemas would otherwise sit in the cache with
            # their nodes empty - invisible to the search. Opening the window runs this through the
            # active database's completion. A no-op once every cached database is loaded.
            $null = Add-SqlSchemaCachedDatabaseNode

            # The subtree was rebuilt from scratch above, so every node under it is visible again.
            # Re-apply whatever the user has typed in the filter box, otherwise switching tab or data
            # connection - or expanding a second database - silently drops an active filter.
            Update-SqlSchemaTreeFilter
        }

        # Built once per response and reused for every later push of the same one.
        $SchemaObjectsJson = Get-SqlSchemaEditorJson -SchemaCacheKey $SchemaCacheKey -SchemaResponse $ReturnValue

        # Sizes at VERBOSE; the schema itself only at VERBOSE2. Logged whole at VERBOSE, it was 30,000
        # and more lines per large database, a quarter of a second each on the UI thread, and the
        # names of every table and column in the customer's database in a log a user can export
        # (issue #61 section 5). The indented form is built only when VERBOSE2 will show it.
        $Private:TableTotal = 0
        foreach ($Private:Property in $ReturnValue.d.PSObject.Properties) {
            if ($Private:Property.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty) {
                $Private:TableTotal++
            }
        }

        "Schema for Monaco editor: {0} table(s), {1} character(s)." -f $Private:TableTotal, $SchemaObjectsJson.Length | Write-LogOutput -LogType VERBOSE
        if (Test-LogTypeShown -LogType VERBOSE2) {
            "Schema for Monaco editor: {0}" -f (ConvertTo-SqlSchemaEditorModel -SchemaResponse $ReturnValue | ConvertTo-Json -Depth 5) | Write-LogOutput -LogType VERBOSE2
        }
        $OnCompletedScriptBlock = {
            param($Pending)
            try {
                # THIS push's task, taken from the queue item - not $Script:Task.
                #
                # $Script:Task is the ACTIVE tab's pending editor task, which by the time this runs is
                # very often a different, still-running one: Set-ActiveTabContext swaps it per tab,
                # and a schema push during start-up races the editor loads of every other restored
                # tab. Reading it reported the wrong task's status, and reported it as a failure
                # ("WaitingForActivation" is a perfectly normal transient state for a task that has
                # not finished). At ERROR that also means a modal dialog per occurrence, which is the
                # cascade of pop-ups seen when reconnecting several tabs at start-up.
                #
                # The poll timer only invokes this once $Pending.Task.IsCompleted, so the item's own
                # task is by definition finished and its status is the real answer.
                $Private:Task = $Pending.Task
                if ($null -eq $Private:Task) {
                    return
                }

                if ($Private:Task.Status -ne "RanToCompletion") {
                    # WARNING -SkipDialog, never ERROR: failing to push IntelliSense metadata into
                    # the editor costs the user completion hints, not their work, and it must not
                    # interrupt them with a dialog - least of all several at once during start-up.
                    "Monaco editor schema push did not complete: {0}" -f $Private:Task.Status | Write-LogOutput -LogType WARNING -SkipDialog
                }
                else {
                    "Monaco Editor Task completed successfully." | Write-LogOutput -LogType DEBUG
                }
            }
            catch {
                $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
            }
        }

        "Push schema to Monaco editor." | Write-LogOutput -LogType DEBUG

        if ($Private:Active) {
            Invoke-ExecuteScriptAsync -ScriptToExecute "setSchema($SchemaObjectsJson);" -OnCompletedScriptBlock $OnCompletedScriptBlock

            # The editor cannot recognise "[SomeDatabase]." as a database reference without knowing
            # which names are databases, and it is the editor that decides when to ask for one.
            Push-SqlDatabaseNameList -ActiveDataConnectionDoId $DataConnectionDoId -OnCompletedScriptBlock $OnCompletedScriptBlock

            # Re-validate after a schema push. A new connection can invalidate the diagnostics that
            # are currently on screen, and it is also the first moment a restored tab's editor
            # content has ever been looked at. Debounced like every other trigger, so switching
            # connection rapidly costs one parse, not one per switch.
            Request-SqlSyntaxValidation -TabSession (Get-ActiveTabSession)
        }
        else {
            # A non-active database goes into its OWN editor model, never into setSchema: overwriting
            # the primary model would make the completion list describe a database the user is not
            # connected to (issue #158 keeps the two-part path exactly as it was).
            #
            # One database per call, rather than one payload carrying every schema. A tenant with a
            # dozen connections would otherwise serialise all of them into a single
            # ExecuteScriptAsync string on every push.
            $Private:DatabaseLiteral = ConvertTo-JavaScriptLiteral -Value $Private:DisplayName
            Invoke-ExecuteScriptAsync -ScriptToExecute "setSchemaForDatabase($Private:DatabaseLiteral, $SchemaObjectsJson);" -OnCompletedScriptBlock $OnCompletedScriptBlock

            # Deliberately NO Request-SqlSyntaxValidation here. The diagnostics on screen describe the
            # active database, and a second database's schema arriving does not change them. Issue
            # #158's validation commit re-triggers once, from the message handler that asked for this
            # schema, rather than once per database that happens to land.
        }
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
