function Add-SqlSchemaCachedDatabaseNode {
    <#
    .SYNOPSIS
        Fills every database node of the schema tree whose schema is already cached. Makes no request.

    .DESCRIPTION
        Issue #165. Start-SqlSchemaPreload caches every database's schema shortly after connect, but
        it only fills the tree when the schema window is open as the responses land
        (Complete-SqlSchemaRetrieval). Open the window afterwards - the usual order - and
        Update-SqlSchemaDatabaseTree builds each database as an empty node with a "Loading..."
        placeholder. The schemas are in hand, yet the search could not see them: the filter skips a
        database that is not loaded, so a table in a folded database was simply not found.

        CALLED WHEN THE WINDOW'S OWN SCHEMA LANDS, and again before every search. Complete-SqlSchemaRetrieval
        runs it after populating the database it was called for, which is what opening the window
        does, so every cached database is searchable from the start. That used to cost about 1.5 s per
        ~500 tables, so it waited for the first search; since Add-SqlSchemaTreeNode defers the column
        nodes it is a few hundred milliseconds for a large tenant. The filter's call stays as the
        backstop, and finds everything loaded - it only walks the database level then.

        A database whose schema is NOT cached - the preload was unavailable, or its response has not
        landed yet - is left as it is. When that response arrives, Complete-SqlSchemaRetrieval fills the
        node and re-applies the filter.

        Requested is set together with Loaded, so expanding a filled node does not fetch it again.

    .OUTPUTS
        [int] the number of databases filled.
    #>
    [CmdLetBinding()]
    [OutputType([int])]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if ($null -eq $Script:TreeViewSqlSchema -or $null -eq $Script:SqlSchemaCache -or $Script:SqlSchemaCache.Count -eq 0) {
            return 0
        }

        $Private:Filled = 0
        foreach ($Private:DatabaseNode in @($Script:TreeViewSqlSchema.Items)) {
            $Private:Tag = $Private:DatabaseNode.Tag
            if ($null -eq $Private:Tag -or $Private:Tag.Loaded) {
                continue
            }

            $Private:CacheKey = Get-SqlSchemaCacheKey -DataConnectionDoId $Private:Tag.DoId
            if ([string]::IsNullOrWhiteSpace($Private:CacheKey) -or -not $Script:SqlSchemaCache.ContainsKey($Private:CacheKey)) {
                continue
            }

            $Private:TableCount = Add-SqlSchemaTreeNode -Parent $Private:DatabaseNode -SchemaResponse $Script:SqlSchemaCache[$Private:CacheKey]
            $Private:Tag.Loaded = $true
            $Private:Tag.Requested = $true
            $Private:Filled++

            "Schema tree for '{0}' filled from the cache: {1} table(s)" -f $Private:Tag.Name, $Private:TableCount | Write-LogOutput -LogType DEBUG
        }

        if ($Private:Filled -gt 0) {
            "Filled {0} database(s) of the schema tree from the cache." -f $Private:Filled | Write-LogOutput -LogType DEBUG
        }

        return $Private:Filled
    }
    catch {
        # Contained: reached from the filter box's TextChanged handler. A database that could not be
        # filled stays as it was - matched on its name, and filled when the user expands it.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        return 0
    }
}
