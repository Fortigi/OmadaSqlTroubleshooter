function Update-SqlSchemaTreeFilter {
    <#
    .SYNOPSIS
    Applies the schema filter to the SQL schema TreeView by hiding non-matching nodes.

    .DESCRIPTION
    The tree is built imperatively in Get-SqlSchemaObject (schema -> table -> column), so filtering
    toggles TreeViewItem.Visibility instead of rebuilding the tree. That keeps the hierarchy, the
    expansion state and the column children intact, and costs no extra round-trip to Omada.

    Visibility rules:
    - A table is visible when its own name matches, or when its parent schema name matches.
    - A schema is visible when its own name matches or when at least one of its tables matches.
      A schema name hit therefore reveals the complete table list of that schema.
    - Columns are never filtered: expanding a visible table always shows all of its columns.

    Called without -FilterValue the function re-applies whatever is currently typed in the filter
    box, which is what Get-SqlSchemaObject needs after it rebuilt the tree for another connection.
    #>
    [CmdLetBinding()]
    param(
        [string]$FilterValue
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

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

        $VisibleTableCount = 0
        foreach ($SchemaItem in $Script:TreeViewSqlSchema.Items) {
            # A null pattern means "no filter": every schema matches, so every table below it stays
            # visible without evaluating a pattern at all.
            $SchemaMatches = ($null -eq $Pattern) -or ($SchemaItem.Header -like $Pattern)

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

            $VisibleTableCount += $VisibleTablesInSchema
        }

        "Sql schema filter '{0}' (pattern '{1}'): {2} table(s) visible" -f $FilterValue, $Pattern, $VisibleTableCount | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
