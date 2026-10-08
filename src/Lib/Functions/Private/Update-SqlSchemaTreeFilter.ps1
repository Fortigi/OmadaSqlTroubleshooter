function Update-SqlSchemaTreeFilter {
    <#
    .SYNOPSIS
    Applies the schema filter to the SQL schema TreeView by hiding non-matching nodes.

    .DESCRIPTION
    The tree is built imperatively (database -> schema -> table -> column), so filtering toggles
    TreeViewItem.Visibility instead of rebuilding the tree. That keeps the hierarchy, the expansion
    state and the column children intact, and costs no extra round-trip to Omada.

    Visibility rules:
    - A table is visible when its own name matches, or when its parent schema or database name
      matches.
    - A schema is visible when its own name matches, when its database name matches, or when at
      least one of its tables matches. A schema name hit therefore reveals the complete table list
      of that schema.
    - A database is visible when its own name matches or when anything below it matches.
    - Columns are never filtered: expanding a visible table always shows all of its columns.

    A DATABASE WHOSE SCHEMA IS CACHED IS FILLED BEFORE THE FIRST SEARCH (issue #165). The preload
    caches every database's schema shortly after connect, but the window is usually opened later and
    builds those databases as empty nodes - so the search missed every table in a folded database.
    Add-SqlSchemaCachedDatabaseNode fills them from the cache, without a request, as soon as a filter
    is typed; the first search pays the build once, and opening the window stays fast.

    A DATABASE WHOSE SCHEMA IS NOT CACHED AT ALL is still never expanded by the filter, and matches on
    its own name only (issue #158). Expanding it is what triggers its fetch, so expanding every
    name-matching database would turn typing in the filter box into a burst of authenticated round
    trips. It contributes no schema or table hits, because the client has nothing to match them
    against; when its response lands, Complete-SqlSchemaRetrieval fills it and re-applies the filter.
    A database that IS loaded expands to its hits.

    Called without -FilterValue the function re-applies whatever is currently typed in the filter
    box, which is what Complete-SqlSchemaRetrieval needs after it rebuilt a database's subtree.
    #>
    [CmdLetBinding()]
    param(
        [string]$FilterValue
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        # The schema window is optional: the schema itself is also retrieved to feed the editor's
        # IntelliSense, so there is nothing to filter when the window was never opened.
        if ($null -eq $Script:TreeViewSqlSchema) {
            "Sql schema tree is not available, skip filtering" | Write-LogOutput -LogType DEBUG
            return
        }

        if (!$PSBoundParameters.ContainsKey("FilterValue")) {
            $FilterValue = ""
            if ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Elements -and $null -ne $Script:SqlSchemaForm.Elements.TextBoxSchemaFilter) {
                $FilterValue = $Script:SqlSchemaForm.Elements.TextBoxSchemaFilter.Text
            }
        }

        $Pattern = ConvertTo-WildcardFilterPattern -FilterValue $FilterValue

        # Only when there is something to search for: clearing the box must not pay for a build.
        if ($null -ne $Pattern) {
            $null = Add-SqlSchemaCachedDatabaseNode
        }

        $VisibleTableCount = 0
        foreach ($DatabaseItem in $Script:TreeViewSqlSchema.Items) {
            # A null pattern means "no filter": everything matches, so every node below stays visible
            # without evaluating a pattern at all.
            $DatabaseMatches = ($null -eq $Pattern) -or ($DatabaseItem.Header -like $Pattern)

            # A database that has not been fetched holds nothing but its "Loading..." placeholder.
            # Walking it would compare the pattern against that placeholder, and expanding it would
            # fetch - so it is matched on its own name and left closed.
            $DatabaseIsLoaded = ($null -ne $DatabaseItem.Tag) -and [bool]$DatabaseItem.Tag.Loaded

            $VisibleTablesInDatabase = 0
            if ($DatabaseIsLoaded) {
                foreach ($SchemaItem in $DatabaseItem.Items) {
                    $SchemaMatches = $DatabaseMatches -or ($SchemaItem.Header -like $Pattern)

                    $VisibleTablesInSchema = 0
                    foreach ($TableItem in $SchemaItem.Items) {
                        if ($SchemaMatches -or ($TableItem.Header -like $Pattern)) {
                            $TableItem.Visibility = [System.Windows.Visibility]::Visible
                            $VisibleTablesInSchema++
                        }
                        else {
                            $TableItem.Visibility = [System.Windows.Visibility]::Collapsed
                        }
                    }

                    if ($SchemaMatches -or $VisibleTablesInSchema -gt 0) {
                        $SchemaItem.Visibility = [System.Windows.Visibility]::Visible
                        if ($null -ne $Pattern) {
                            # Expand while filtering so the hits are visible without an extra click.
                            $SchemaItem.IsExpanded = $true
                        }
                    }
                    else {
                        $SchemaItem.Visibility = [System.Windows.Visibility]::Collapsed
                    }

                    $VisibleTablesInDatabase += $VisibleTablesInSchema
                }
            }

            if ($DatabaseMatches -or $VisibleTablesInDatabase -gt 0) {
                $DatabaseItem.Visibility = [System.Windows.Visibility]::Visible

                # Only a LOADED database is expanded to show its hits. See the note in the
                # description: expanding an unloaded one is a round trip per keystroke.
                if ($null -ne $Pattern -and $DatabaseIsLoaded -and $VisibleTablesInDatabase -gt 0) {
                    $DatabaseItem.IsExpanded = $true
                }
            }
            else {
                $DatabaseItem.Visibility = [System.Windows.Visibility]::Collapsed
            }

            $VisibleTableCount += $VisibleTablesInDatabase
        }

        "Sql schema filter '{0}' (pattern '{1}'): {2} table(s) visible" -f $FilterValue, $Pattern, $VisibleTableCount | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
