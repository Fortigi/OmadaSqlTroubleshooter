function Start-SqlSchemaPreload {
    <#
    .SYNOPSIS
        Requests every data connection's schema in the background, once the connection list is known.

    .DESCRIPTION
        Issue #165. The schema window used to load one database at a time, on first expand, and
        Update-SqlSchemaDatabaseTree still says why that was right: before issue #40 a fetch blocked the
        UI thread, so N connections meant N sequential freezes. Since #40 the fetch goes to a worker and
        is cached per pool, so the lazy design now only costs the user a stall on every node they have
        not opened yet, and leaves cross-database completion (#158, #152) working for whichever
        databases they happened to expand.

        This dispatches them all instead, one request per connection, as soon as the dropdown is known
        to be current.

        THE ELIGIBILITY GATE IS THE LOAD-BEARING PART OF THIS FUNCTION.

        Test-OmadaBackgroundRequestEligible is asked ONCE, before anything is dispatched, and a "no"
        means no preload at all - the tree keeps its on-expand fetch and the user is exactly where they
        were. That is not defensive tidying. Get-SqlSchemaObject falls back to the SYNCHRONOUS wrapper
        whenever dispatch returns $null, so a loop that ignored this gate would fire one blocking
        authenticated request per database on the UI thread at connect. With a disabled background path
        - which is one observed worker failure away, see Disable-OmadaBackgroundRequest - that turns a
        feature meant to remove a freeze into eight of them.

        The real decision function is used rather than reading the flags it reads. A copy of that
        decision here would be free to drift from it, which is the misclassification the original is
        there to prevent.

        Residual case, stated rather than hidden: after the gate says yes, an INDIVIDUAL dispatch can
        still fail - the pool could not be opened, or a worker file is missing - and that one falls back
        inline. One synchronous request is an acceptable cost for an unusual failure; eight is not,
        which is the whole reason the gate is checked before the loop rather than inside it.

        No cap and no queue of its own. A tenant's connection count is small - eight at the time of
        writing - and the runspace pool is sized to TabCapacity (default 8, floor 2), so a smaller pool
        queues the requests rather than blocking anything.

        Every other guard belongs to Get-SqlSchemaObject and is reused unchanged: the per-pool cache,
        the in-flight check against the completion queue, the connection gate, and the UI-thread retry.
        This function adds no caching and no bookkeeping of its own.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip reconnect" | Write-LogOutput -LogType DEBUG
            return
        }

        # The active tab's own connection flag, for the same reason Get-SqlSchemaObject reads it: a
        # restored but deliberately disconnected tab satisfies every other check, and preloading there
        # would authenticate against the tenant behind -NoReconnect (issue #64).
        if (-not $Script:ConnectionStatus) {
            "Tab is not connected; not preloading schemas." | Write-LogOutput -LogType DEBUG
            return
        }

        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        if (-not (Test-OmadaBackgroundRequestEligible -Parameters (Build-OmadaRequestParameter))) {
            # See above: without the preload the tree fetches on first expand, which is the behaviour
            # this feature replaces - slower for the user, but never a freeze.
            "Background requests are not available; leaving each schema to load when its node is expanded." | Write-LogOutput -LogType DEBUG
            return
        }

        # -NoRefresh: this runs on the UI thread from a request completion, and a synchronous tenant
        # refresh hidden inside a preload would block the window. Nothing is lost - the only caller is
        # the list update itself, so the list is current by definition.
        #
        # Not wrapped in @(): the function returns its array through the ", $array" idiom, and wrapping
        # it again nests the array one level deeper, which turns every .DoId below into an array.
        $Private:Reference = Get-DataConnectionReferenceList -OptionList (Get-DataConnectionOptionText -NoRefresh)
        if ($Private:Reference.Count -eq 0) {
            "The data connection list is empty; nothing to preload." | Write-LogOutput -LogType DEBUG
            return
        }

        $Private:ActiveDoId = [string]$Script:AppConfig.CurrentDataConnection.DoId
        $Private:Dispatched = 0

        foreach ($Private:Connection in $Private:Reference) {
            # A DoId that is not a positive integer names no database, so it is not worth a request.
            # Get-SqlSchemaObject refuses it too (issue #165) and that is the gate that matters - this
            # one keeps the preload's own count honest, because a skipped entry is not "requested".
            # Invariant culture, as everywhere else in the module that parses a machine-formatted
            # value - see the same guard in Get-SqlSchemaObject.
            $Private:ParsedDoId = 0
            if (-not ([int]::TryParse([string]$Private:Connection.DoId, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Private:ParsedDoId)) -or $Private:ParsedDoId -le 0) {
                continue
            }

            if ([string]$Private:Connection.DoId -eq $Private:ActiveDoId) {
                # The normal path already fetches the active connection, and asking again here would be
                # a duplicate request for the database the window is loading anyway.
                continue
            }

            $Private:CacheKey = Get-SqlSchemaCacheKey -DataConnectionDoId $Private:Connection.DoId
            if ($null -ne $Script:SqlSchemaCache -and $Script:SqlSchemaCache.ContainsKey($Private:CacheKey)) {
                continue
            }

            # Marked before dispatch, so a user who expands this node while its response is in flight
            # does not ask for it a second time. Get-SqlSchemaObject's in-flight check would catch that
            # too; this also keeps the node's own state honest about having been asked.
            $Private:Node = Get-SqlSchemaDatabaseNode -DataConnectionDoId $Private:Connection.DoId
            if ($null -ne $Private:Node -and $null -ne $Private:Node.Tag) {
                $Private:Node.Tag.Requested = $true
            }

            Get-SqlSchemaObject -DataConnectionDoId $Private:Connection.DoId -DataConnectionName $Private:Connection.Name
            $Private:Dispatched++
        }

        "Schema preload: requested {0} of {1} data connection(s)." -f $Private:Dispatched, $Private:Reference.Count | Write-LogOutput -LogType DEBUG
    }
    catch {
        # Contained: reached from the completion poll timer, where a terminating log would unwind into
        # the timer's own Tick handler. A failed preload costs the user a stall on first expand, which
        # is the behaviour this replaces - never their work.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
