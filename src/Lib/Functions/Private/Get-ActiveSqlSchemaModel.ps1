function Get-SqlSchemaCacheKey {
    <#
    .SYNOPSIS
        Returns the "<SessionKey>|<DataConnectionDoId>" key under which a given data connection's
        schema is cached, or $null when there is no connection pool to key it against.

    .DESCRIPTION
        The format lived only in Get-ActiveSqlSchemaCacheKey until issue #158, which needs the key of
        a data connection that is NOT the active one - the schema window now holds a node per
        connection and fetches each one's schema on first expand. That is the same cache, under the
        same per-pool contract, for a different DoId.

        Still exactly one formatter. The reason Get-ActiveSqlSchemaCacheKey gives for that is
        unchanged and now covers more callers: a second copy of this string would be another chance
        for the validation pass, the completion list and the schema window to disagree about which
        tenant's schema they are looking at.

    .PARAMETER DataConnectionDoId
        The data connection's DoId.

    .OUTPUTS
        [string] the cache key, or $null.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DataConnectionDoId
    )

    # No tracer preamble: called from the debounced validation path on every idle tick.

    if ($null -eq $Script:RunTimeData -or $null -eq $Script:RunTimeData.RestMethodParam) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($DataConnectionDoId)) {
        return $null
    }

    return "{0}|{1}" -f $Script:RunTimeData.RestMethodParam.SessionKey, $DataConnectionDoId
}

function Get-ActiveSqlSchemaCacheKey {
    <#
    .SYNOPSIS
        Returns the "<SessionKey>|<DataConnectionDoId>" key under which the active tab's schema is
        cached, or $null when the tab has no data connection yet.

    .DESCRIPTION
        The key is built in exactly one place - here - because three callers now need it:
        Get-SqlSchemaObject to look the schema up, Reset-SqlSchemaCache to throw it away, and the
        schema validation pass to resolve identifiers against it. Three copies of a string format
        would be three chances for the validation pass to read a different tenant's schema than the
        editor is showing completions for.

    .OUTPUTS
        [string] the cache key, or $null.
    #>
    [CmdLetBinding()]
    param()

    # No tracer preamble: called from the debounced validation path on every idle tick.

    if ($null -eq $Script:AppConfig -or $null -eq $Script:AppConfig.CurrentDataConnection -or
        [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
        return $null
    }

    return Get-SqlSchemaCacheKey -DataConnectionDoId $Script:AppConfig.CurrentDataConnection.DoId
}

function Get-ActiveSqlSchemaModel {
    <#
    .SYNOPSIS
        Returns the indexed schema for the active tab's data connection, or $null when there is none
        cached.

    .DESCRIPTION
        The schema validation pass of issue #61 makes NO request: it resolves identifiers against the
        schema the application already fetched for IntelliSense (acceptance criterion 2 and 5). This
        is the whole of its access to that schema, and it never fetches - a tab whose schema has not
        arrived yet simply gets no schema diagnostics.

        The indexed form is memoised next to the raw cache rather than rebuilt per keystroke: indexing
        a large tenant schema is thousands of string splits, and the debounce would pay for it on
        every idle tick. Complete-SqlSchemaRetrieval drops the memo whenever it writes a new response
        for a key, so the index can never outlive the response it was built from.

    .OUTPUTS
        The model from Get-SqlSchemaModel, or $null.
    #>
    [CmdLetBinding()]
    param()

    # No tracer preamble: called from the debounced validation path on every idle tick.

    try {
        $CacheKey = Get-ActiveSqlSchemaCacheKey
        if ([string]::IsNullOrWhiteSpace($CacheKey)) {
            return $null
        }

        if ($null -eq $Script:SqlSchemaCache -or -not $Script:SqlSchemaCache.ContainsKey($CacheKey)) {
            return $null
        }

        if ($null -eq $Script:SqlSchemaModelCache) {
            $Script:SqlSchemaModelCache = @{}
        }

        if (-not $Script:SqlSchemaModelCache.ContainsKey($CacheKey)) {
            $Script:SqlSchemaModelCache[$CacheKey] = Get-SqlSchemaModel -SchemaResponse $Script:SqlSchemaCache[$CacheKey]
        }

        return $Script:SqlSchemaModelCache[$CacheKey]
    }
    catch {
        # No schema is a supported state for the pass, so a failure to produce one degrades to it
        # rather than surfacing. The message can name tenant objects, so it is not logged.
        "The cached SQL schema could not be indexed; schema diagnostics are unavailable for this run." | Write-LogOutput -LogType DEBUG
        return $null
    }
}

function Reset-SqlSchemaCache {
    <#
    .SYNOPSIS
        Throws away every cached schema for this connection pool and fetches them again.

    .DESCRIPTION
        The "Refresh schema" action of issue #61 section 2. The schema cache lives for the whole
        session, which is right for a schema that does not change - and wrong the moment it does.
        A stale cache is the reason the schema pass only ever warns, but the user still needs a way
        to say "it changed, look again" without restarting the application.

        EVERY DATABASE IN THE POOL, not just the active one (issue #165). The window now shows every
        data connection with its schema already loaded, so "refresh" that dropped one database's cache
        would leave the rest of the tree showing whatever it read on connect - stale, and silently so.
        Keys are matched on the "<SessionKey>|" prefix the schema cache is keyed by, so another
        session's tabs keep their caches.

        All three caches go for each of them: the raw response, the index built from it, and the
        editor JSON built from it.
        Get-SqlSchemaObject then re-fetches the active connection - repopulating the tree, pushing the
        schema to the editor and re-triggering validation, the same path a connection change takes -
        and Start-SqlSchemaPreload asks for the rest.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $CacheKey = Get-ActiveSqlSchemaCacheKey
        if ([string]::IsNullOrWhiteSpace($CacheKey)) {
            "No data connection is selected, so there is no cached schema to refresh." | Write-LogOutput -LogType DEBUG
            return
        }

        # The pool's own prefix, taken from the active key rather than rebuilt from RestMethodParam, so
        # this cannot disagree with Get-SqlSchemaCacheKey about how a key is shaped.
        $Private:PoolPrefix = "{0}|" -f $CacheKey.Split("|")[0]

        foreach ($Private:Cache in @($Script:SqlSchemaCache, $Script:SqlSchemaModelCache, $Script:SqlSchemaEditorJsonCache)) {
            if ($null -eq $Private:Cache) {
                continue
            }

            # Keys snapshotted: the collection is modified in the loop.
            foreach ($Private:Key in @($Private:Cache.Keys)) {
                if ([string]$Private:Key -like ("{0}*" -f $Private:PoolPrefix)) {
                    $Private:Cache.Remove($Private:Key)
                }
            }
        }

        "Refreshing the SQL schema." | Write-LogOutput

        Get-SqlSchemaObject
        Start-SqlSchemaPreload
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
