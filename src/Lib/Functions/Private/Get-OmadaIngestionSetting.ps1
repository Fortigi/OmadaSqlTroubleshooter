# The label the ingestion probe carries on the completion queue. A constant because it is MATCHED, not
# just displayed: Start-OmadaIngestionSettingProbe reads the queue through it to decide whether a probe
# for this session is already outstanding - the same arrangement as $Script:SqlSchemaRequestDescription
# at the top of Get-SqlSchema.ps1. Left undefined it would be $null, which matches every unlabelled
# item on the queue and would stop the probe from ever dispatching.
$Script:OmadaIngestionProbeDescription = "ODW ingestion setting"

function Get-OmadaIngestionSetting {
    <#
    .SYNOPSIS
        The tenant's ODW ingestion flag as this session has already learned it, or $null.

    .DESCRIPTION
        Issue #165. CACHE-ONLY, and deliberately so: it never makes a request, so the filter that uses
        it can run at any point - including the first build of the data connection list, before the
        probe has answered - without blocking the window or dragging a round trip into a render path.

        Three state, and the distinction is the whole contract:

          $true   ingestion is on, so the unused ODW connections may be filtered;
          $false  ingestion is off, so they may not;
          $null   this session does not know yet, has not asked, or asked and failed - which must be
                  treated exactly like $false by the filter. Hiding a database the user needs is worse
                  than offering one that does not work, which is what the application did before.

        Per CONNECTION POOL, not per tab and not per connect. The key is the SessionKey, the same
        component Get-SqlSchemaCacheKey builds its own key from: one tenant session gives one answer,
        and every tab sharing that session reuses it.

    .OUTPUTS
        [bool] or $null.
    #>
    [CmdLetBinding()]
    param()

    # No tracer preamble: called from the render path on every list update, and it answers from memory.

    $Private:Key = Get-OmadaIngestionSettingCacheKey
    if ([string]::IsNullOrWhiteSpace($Private:Key)) {
        return $null
    }

    if ($null -eq $Script:OmadaIngestionSettingCache -or -not $Script:OmadaIngestionSettingCache.ContainsKey($Private:Key)) {
        return $null
    }

    return $Script:OmadaIngestionSettingCache[$Private:Key]
}

function Get-OmadaIngestionSettingCacheKey {
    <#
    .SYNOPSIS
        The cache key for the current connection pool, or an empty string when there is none.

    .DESCRIPTION
        The SessionKey alone. Unlike the schema cache there is no data connection in the key: the flag
        is a property of the TENANT, not of a database, so every connection in one session shares it.

    .OUTPUTS
        [string] possibly empty.
    #>
    [CmdLetBinding()]
    param()

    return [string]$Script:RunTimeData.RestMethodParam.SessionKey
}

function Start-OmadaIngestionSettingProbe {
    <#
    .SYNOPSIS
        Learns the tenant's ODW ingestion flag, in the background, once per connection pool.

    .DESCRIPTION
        Issue #165. The flag lives in the `appPageVars` block that every Omada page embeds, so it costs
        ONE request to read. The alternative - running
        `SELECT [ValueStr] FROM [dbo].[tblApplicationSetting] WHERE [key] = 'odwIngestionEnabled'` -
        goes through Invoke-OmadaExecutePipeline, which is up to four round trips AND creates and
        deletes a TMP_ query object on the tenant. The page read has no side effects at all, which is
        why the SQL probe was dropped rather than kept as a fallback.

        Does nothing when the answer is already cached, so a second tab on the same session is free.

        GUARDED BY $Script:ConnectionStatus, exactly as Get-SqlSchemaObject is. Without it a restored
        but deliberately disconnected tab would reach the tenant on its own - the defect issue #64
        fixed - and it would defeat -NoReconnect and a declined reconnect prompt alike.

        POST with no body, which is the shape verified against a live tenant; the page answers with the
        same markup either way. Only the flag is read from the response - never the body of the page,
        and never the parsed settings as a whole, because that blob carries AD topology, environment
        identifiers and endpoint configuration that have no business in a log.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if (-not $Script:ConnectionStatus) {
            "Tab is not connected; not probing the ODW ingestion setting." | Write-LogOutput -LogType DEBUG
            return
        }

        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        $Private:Key = Get-OmadaIngestionSettingCacheKey
        if ([string]::IsNullOrWhiteSpace($Private:Key)) {
            return
        }

        if ($null -eq $Script:OmadaIngestionSettingCache) {
            $Script:OmadaIngestionSettingCache = @{}
        }

        if ($Script:OmadaIngestionSettingCache.ContainsKey($Private:Key)) {
            return
        }

        # Read off the completion queue rather than kept in a side table of "probes in flight", for the
        # reason Get-SqlSchemaObject gives: a side table has to be cleared on every path a request can
        # leave by, and an entry left behind would block this pool from ever learning the flag again.
        if (@($Script:PendingWebViewCompletions | Where-Object { $_.Description -eq $Script:OmadaIngestionProbeDescription }).Count -gt 0) {
            return
        }

        $Script:RunTimeData.RestMethodParam.Uri = "{0}/logon.aspx" -f $Script:AppConfig.BaseUrl
        $Script:RunTimeData.RestMethodParam.Method = "POST"
        $Script:RunTimeData.RestMethodParam.Body = $null

        # The cache key travels on the context rather than being re-derived in the completion: by the
        # time that runs, the user may have switched to a tab on a different session, and the answer
        # belongs to the session that was asked.
        $Private:Pending = Invoke-OmadaPSWebRequestWrapperAsync -Description $Script:OmadaIngestionProbeDescription -Context @{
            CacheKey = $Private:Key
        } -OnResultScriptBlock {
            param($Pending)

            Complete-OmadaIngestionSettingProbe -Response $Pending.Outcome -CacheKey $Pending.Context.Caller.CacheKey
        }

        if ($null -ne $Private:Pending) {
            return
        }

        # Not eligible for a worker, or none available. One request inline is acceptable here - it is a
        # single read with no tenant side effects - which is NOT true of the schema fan-out, where the
        # same fallback would mean one synchronous request per database on connect.
        Complete-OmadaIngestionSettingProbe -Response (Invoke-OmadaPSWebRequestWrapper) -CacheKey $Private:Key
    }
    catch {
        # Contained: this runs from a list-update completion, where a terminating log would unwind into
        # the poll timer rather than into anything that can act on it. Not knowing the flag is a
        # recoverable state - the list simply stays unfiltered.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Complete-OmadaIngestionSettingProbe {
    <#
    .SYNOPSIS
        Caches the ingestion flag from a probe response and applies it to the connection list.

    .DESCRIPTION
        Split out of Start-OmadaIngestionSettingProbe so the same work runs whether the response came
        from a worker or inline, exactly as Complete-SqlSchemaRetrieval is split from Get-SqlSchemaObject.
        It touches WPF, so it is UI thread only - which it always is: the background path reaches it
        from the completion poll timer, with the owning tab already made active.

        ONLY A DEFINITE ANSWER IS CACHED. A failed request, a page this parser cannot read, or a page
        with no such setting leaves the cache empty, so the next connect on this session asks again.
        Caching "unknown" would turn one bad response into a session-long refusal to filter.

        The flag is logged; the settings blob is not. The page carries AD topology, environment
        identifiers and endpoint configuration, and a log a user can export and attach to a ticket is
        the wrong place for any of it.

    .PARAMETER Response
        What the request produced: the page, an ErrorRecord, or $null.

    .PARAMETER CacheKey
        The SessionKey this answer belongs to. Passed in rather than re-derived, because the active tab
        may have changed since the probe was dispatched.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Response,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$CacheKey
    )

    try {
        if ($null -eq $Response -or $Response -is [System.Management.Automation.ErrorRecord]) {
            "The ODW ingestion setting could not be read; the data connection list stays unfiltered." | Write-LogOutput -LogType DEBUG
            return
        }

        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html ([string]$Response)
        if ($null -eq $Private:Setting -or -not $Private:Setting.Contains("isIngestionEnabled")) {
            # Absent is not false: an older tenant that does not publish the flag has not said
            # ingestion is off, so nothing is filtered.
            #
            # But it IS an answer, and it is cached as $null for that reason. The page was read and it
            # does not carry the setting; asking the same tenant again on the next connect cannot
            # produce a different result, and not caching it meant exactly that - one request per
            # connect, for the rest of the session. The three-state contract is unaffected, because
            # the cache is read through ContainsKey: a cached $null means "asked, not published",
            # which Remove-UnusedDataConnection already treats like "off".
            #
            # Initialised here as well as on the success path below: this branch can be reached with a
            # cold cache (Complete- is also called directly by the inline fallback), and writing into
            # a $null hashtable would throw into the contained catch - leaving the re-probe in place
            # with nothing to show that the fix had not taken effect.
            if ($null -eq $Script:OmadaIngestionSettingCache) {
                $Script:OmadaIngestionSettingCache = @{}
            }
            $Script:OmadaIngestionSettingCache[$CacheKey] = $null
            "The page carries no ingestion setting; the data connection list stays unfiltered." | Write-LogOutput -LogType DEBUG
            return
        }

        $Private:Enabled = [bool]$Private:Setting["isIngestionEnabled"]

        if ($null -eq $Script:OmadaIngestionSettingCache) {
            $Script:OmadaIngestionSettingCache = @{}
        }
        $Script:OmadaIngestionSettingCache[$CacheKey] = $Private:Enabled

        "ODW ingestion enabled: {0}" -f $Private:Enabled | Write-LogOutput -LogType DEBUG

        # The list was built before the answer arrived, which is the ordering the issue asks for: the
        # tables are retrieved as they always were, and the filter is applied afterwards. Pruning the
        # dropdown is all that is needed - Update-SqlSchemaDatabaseTree removes the nodes of a
        # connection that has left it, and Push-SqlDatabaseNameList re-pushes what the editor may
        # complete, both reading the dropdown back.
        Remove-FilteredDataConnectionItem
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
