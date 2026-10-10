function New-SqlSchemaTreeItem {
    <#
    .SYNOPSIS
        Creates one TreeViewItem for the SQL schema window.

    .DESCRIPTION
        A one-line factory, and deliberately its own function rather than three inline
        New-Object blocks. Add-SqlSchemaTreeNode and Update-SqlSchemaDatabaseTree build the tree out
        of these, so stubbing this function is what lets a Pester test assert the SHAPE of the tree -
        which level carries which header - without WPF and without an STA runspace. The levels are
        the part issue #158 changes, so they are the part that needs covering.

    .PARAMETER Header
        The text shown for the node.

    .PARAMETER FontSize
        Carried over from the code this replaces: 14 for a database, schema or table, 12 for a column.

    .PARAMETER IsExpanded
        Whether the node starts expanded.

    .PARAMETER Tag
        Arbitrary state to hang off the node. Update-SqlSchemaDatabaseTree uses it for the data
        connection's DoId and its loaded flag.

    .OUTPUTS
        [System.Windows.Controls.TreeViewItem]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Header,

        [Parameter(Mandatory = $false, Position = 1)]
        [int]$FontSize = 14,

        [Parameter(Mandatory = $false)]
        [switch]$IsExpanded,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Tag
    )

    # No tracer preamble: the header is tenant-derived schema, table and column text (issue #61
    # section 5), and this runs once per node - thousands of times for a large tenant.

    # The constructor, not New-Object: this runs once per node, and New-Object's cmdlet overhead was a
    # measurable part of building a large database's tree.
    $Item = [System.Windows.Controls.TreeViewItem]::new()
    $Item.Header = $Header
    $Item.FontSize = $FontSize
    $Item.IsExpanded = $IsExpanded.IsPresent

    if ($PSBoundParameters.ContainsKey("Tag")) {
        $Item.Tag = $Tag
    }

    return $Item
}

function Add-SqlSchemaTreeNode {
    <#
    .SYNOPSIS
        Builds the schema -> table -> column nodes of one database underneath a parent node.

    .DESCRIPTION
        Extracted from Complete-SqlSchemaRetrieval by issue #158. The tree used to be exactly three
        levels hanging off the TreeView itself, so the builder could assume its parent. It now has a
        data connection level on top, and the same three levels have to be built either under the
        TreeView (there is no such case left, but the shape is unchanged) or under a database node -
        so the parent is a parameter.

        The parent's existing children are replaced. For a database node that is what swaps the
        "Loading..." placeholder for the real schema; for any node it is what makes a refresh
        idempotent instead of appending a second copy of the tree.

        Both a TreeView and a TreeViewItem expose .Items, so the parameter is deliberately untyped
        and either one works.

        COLUMNS ARE BUILT WHEN THEIR TABLE IS EXPANDED, not here. A table node carries its columns on
        its Tag and a "Loading..." placeholder for the expander arrow; Add-SqlSchemaTreeColumnNode
        turns them into nodes on first expand. Building them all up front made a 565-table database
        9,060 tree items and 4.5 s on the UI thread; this is 1,150 items and a third of a second.
        Nothing is lost by it: the filter never searches columns, and a column node can only be seen,
        clicked or shift-clicked after its table has been expanded.

        One pass over the tables, grouping them by schema as it goes, rather than filtering every
        table again for each schema.

    .PARAMETER Parent
        The TreeView or TreeViewItem to build under.

    .PARAMETER SchemaResponse
        The GetSqlSchema response for the database this node represents: the payload is on its .d
        property.

    .OUTPUTS
        [int] the number of tables added, for the caller's log line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $Parent,

        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        $SchemaResponse
    )

    # No tracer preamble: the response names every table and column in the customer's database
    # (issue #61 section 5).

    $Parent.Items.Clear()

    $Payload = if ($null -eq $SchemaResponse -or $SchemaResponse -is [System.Management.Automation.ErrorRecord]) { $null } else { $SchemaResponse.d }
    if ($null -eq $Payload) {
        return 0
    }

    $TableCount = 0
    $SchemaItemByName = @{}

    foreach ($Property in $Payload.PSObject.Properties) {
        # NoteProperties only, which is exactly what Get-Member -MemberType NoteProperty returned: a
        # payload that is not an object (a string, say) has CLR properties such as Length too.
        if ($Property.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty) {
            continue
        }

        $Part = $Property.Name.Split(".", 2)
        $SchemaName = $Part[0]

        $SchemaItem = $SchemaItemByName[$SchemaName]
        if ($null -eq $SchemaItem) {
            # Expanded, exactly as the three-level tree always was. Issue #158 asks for the selected
            # database to look "exactly as today" once its node is open, and this is that.
            $SchemaItem = New-SqlSchemaTreeItem -Header $SchemaName -FontSize 14 -IsExpanded
            $Parent.Items.Add($SchemaItem) | Out-Null
            $SchemaItemByName[$SchemaName] = $SchemaItem
        }

        # A name without a dot has a schema and no table, which is what the two-pass version made of
        # it too: the schema node, empty.
        if ($Part.Count -lt 2) {
            continue
        }

        # The columns travel on the Tag and become nodes on first expand - see the description. The
        # placeholder is what gives the table its expander arrow until then.
        $TableItem = New-SqlSchemaTreeItem -Header $Part[1] -FontSize 14 -Tag ([PSCustomObject]@{
                Columns      = @($Property.Value)
                ColumnsBuilt = $false
            })
        $TableItem.Items.Add((New-SqlSchemaTreeItem -Header "Loading..." -FontSize 12)) | Out-Null
        $SchemaItem.Items.Add($TableItem) | Out-Null
        $TableCount++
    }

    return $TableCount
}

function Add-SqlSchemaTreeColumnNode {
    <#
    .SYNOPSIS
        Builds a table node's column nodes, the first time the table is expanded.

    .DESCRIPTION
        The deferred half of Add-SqlSchemaTreeNode: the table node carries its columns on its Tag and a
        "Loading..." placeholder, and this replaces the placeholder with one node per column. Reached
        from Invoke-SqlSchemaDatabaseNodeExpanded, which already receives every Expanded event that
        bubbles up from inside its database - so no handler is attached per table.

        Does nothing for a node that is not a table, or whose columns are already built, so a
        collapse-and-expand costs nothing.

    .PARAMETER TableItem
        The table TreeViewItem that was expanded.

    .OUTPUTS
        [bool] $true when columns were built.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        $TableItem
    )

    # No tracer preamble: the columns name the customer's database (issue #61 section 5).

    if ($null -eq $TableItem -or $null -eq $TableItem.Tag -or $TableItem.Tag -isnot [System.Management.Automation.PSCustomObject]) {
        return $false
    }

    if ($null -eq $TableItem.Tag.PSObject.Properties["ColumnsBuilt"] -or $TableItem.Tag.ColumnsBuilt) {
        return $false
    }

    $TableItem.Items.Clear()

    # The column header stays the raw "ColumnName DataType" entry, as it has always been: the window
    # shows the type beside the name, and Invoke-OnTreeViewItemShiftClick splits it back apart on the
    # space when it pushes a column into the editor.
    foreach ($Column in @($TableItem.Tag.Columns)) {
        $TableItem.Items.Add((New-SqlSchemaTreeItem -Header ([string]$Column) -FontSize 12)) | Out-Null
    }

    $TableItem.Tag.ColumnsBuilt = $true
    return $true
}
