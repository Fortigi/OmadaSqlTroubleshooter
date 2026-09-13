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

    if ($null -eq $Script:RunTimeData -or $null -eq $Script:RunTimeData.RestMethodParam) {
        return $null
    }

    if ($null -eq $Script:AppConfig -or $null -eq $Script:AppConfig.CurrentDataConnection -or
        [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
        return $null
    }

    return "{0}|{1}" -f $Script:RunTimeData.RestMethodParam.SessionKey, $Script:AppConfig.CurrentDataConnection.DoId
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
        Throws away the cached schema for the active tab's data connection and fetches it again.

    .DESCRIPTION
        The "Refresh schema" action of issue #61 section 2. The schema cache lives for the whole
        session, which is right for a schema that does not change - and wrong the moment it does.
        A stale cache is the reason the schema pass only ever warns, but the user still needs a way
        to say "it changed, look again" without restarting the application.

        Both caches go: the raw response and the index built from it. Get-SqlSchemaObject then
        re-fetches, repopulates, rebuilds the schema tree, pushes the schema to the editor and
        re-triggers validation - the same path a connection change takes.

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

        if ($null -ne $Script:SqlSchemaCache) {
            $Script:SqlSchemaCache.Remove($CacheKey)
        }

        if ($null -ne $Script:SqlSchemaModelCache) {
            $Script:SqlSchemaModelCache.Remove($CacheKey)
        }

        "Refreshing the SQL schema." | Write-LogOutput

        Get-SqlSchemaObject
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
