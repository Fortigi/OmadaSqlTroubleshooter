function Get-CachedSqlSchemaModelByDatabase {
    <#
    .SYNOPSIS
        Returns the indexed schema of every database CACHED for the current connection pool, keyed by
        the data connection's name.

    .DESCRIPTION
        What lets the schema validation pass say something about a cross-database name (issue #158).
        Until now it skipped every three-part name, because the only schema it had was the active
        connection's - and it still skips the ones it has no schema for. The difference is that the
        schema window and the editor's cross-database completion now populate the per-pool cache for
        other databases too, so for those there is something to resolve against.

        IT NEVER FETCHES. That is the whole contract, and the reason this returns a map rather than
        resolving a name on demand: the pass runs on a debounce, on every idle tick, and issue #61's
        acceptance criteria 2 and 5 say it makes NO request. A database the user has not looked at is
        simply absent here, and the pass then treats that name exactly as it does today.

        Keyed by NAME because that is what the query writes. The cache is keyed by DoId, so the
        dropdown is what maps one to the other - the same mapping Resolve-DataConnectionReference
        uses for the execute path, so completion, execution and validation cannot disagree about
        what "[Other]" means.

        Indexed models are memoised in $Script:SqlSchemaModelCache beside the active one, under the
        same cache key, so a tenant's schema is indexed once per response rather than once per idle
        tick - and Complete-SqlSchemaRetrieval already drops that memo whenever it writes a new
        response for a key.

    .OUTPUTS
        [hashtable] lower(connection name) -> the model from Get-SqlSchemaModel. Empty when nothing
        but the active database is cached, or when there is no pool yet.
    #>
    [CmdLetBinding()]
    param()

    # No tracer preamble: called from the debounced validation path on every idle tick.

    $Result = @{}

    try {
        if ($null -eq $Script:SqlSchemaCache -or $Script:SqlSchemaCache.Count -eq 0) {
            return $Result
        }

        $Private:Reference = Get-DataConnectionReferenceList -OptionList (Get-DataConnectionOptionText)
        if ($Private:Reference.Count -eq 0) {
            return $Result
        }

        if ($null -eq $Script:SqlSchemaModelCache) {
            $Script:SqlSchemaModelCache = @{}
        }

        foreach ($Private:Connection in $Private:Reference) {
            # Through the one formatter, so this cannot read another pool's cache entry: two tenants
            # can both have a connection called "Reporting", and they are different databases.
            $Private:CacheKey = Get-SqlSchemaCacheKey -DataConnectionDoId $Private:Connection.DoId
            if ([string]::IsNullOrWhiteSpace($Private:CacheKey) -or -not $Script:SqlSchemaCache.ContainsKey($Private:CacheKey)) {
                continue
            }

            if (-not $Script:SqlSchemaModelCache.ContainsKey($Private:CacheKey)) {
                $Script:SqlSchemaModelCache[$Private:CacheKey] = Get-SqlSchemaModel -SchemaResponse $Script:SqlSchemaCache[$Private:CacheKey]
            }

            $Private:Model = $Script:SqlSchemaModelCache[$Private:CacheKey]
            if ($null -ne $Private:Model) {
                $Result[$Private:Connection.Name.ToLowerInvariant()] = $Private:Model
            }
        }

        # Count only, never the names (issue #61 section 5).
        "Cached SQL schema available for {0} database(s)." -f $Result.Count | Write-LogOutput -LogType DEBUG
    }
    catch {
        # No schema is a supported state for the pass, so a failure to produce one degrades to it
        # rather than surfacing. The message can name tenant objects, so it is not logged.
        "The cached SQL schemas could not be indexed; cross-database schema diagnostics are unavailable for this run." | Write-LogOutput -LogType DEBUG
        return @{}
    }

    return $Result
}

