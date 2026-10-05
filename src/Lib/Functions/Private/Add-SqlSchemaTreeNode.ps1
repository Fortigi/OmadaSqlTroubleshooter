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

    $Item = New-Object System.Windows.Controls.TreeViewItem
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
    $Property = @($Payload | Get-Member -MemberType NoteProperty)

    $SchemaNameList = @($Property.Name | ForEach-Object { $_.Split(".", 2)[0] } | Select-Object -Unique)
    foreach ($SchemaName in $SchemaNameList) {
        # Expanded, exactly as the three-level tree always was. Issue #158 asks for the selected
        # database to look "exactly as today" once its node is open, and this is that.
        $SchemaItem = New-SqlSchemaTreeItem -Header $SchemaName -FontSize 14 -IsExpanded
        $Parent.Items.Add($SchemaItem) | Out-Null

        foreach ($Table in @($Property | Where-Object { $_.Name -like ("{0}.*" -f $SchemaName) })) {
            $TableFullName = $Table.Name
            $TableItem = New-SqlSchemaTreeItem -Header ($TableFullName.Split(".", 2)[1]) -FontSize 14
            $SchemaItem.Items.Add($TableItem) | Out-Null
            $TableCount++

            # The column header stays the raw "ColumnName DataType" entry, as it has always been:
            # the window shows the type beside the name, and Invoke-OnTreeViewItemShiftClick splits
            # it back apart on the space when it pushes a column into the editor.
            foreach ($Column in @($Payload.$TableFullName)) {
                $TableItem.Items.Add((New-SqlSchemaTreeItem -Header ([string]$Column) -FontSize 12)) | Out-Null
            }
        }
    }

    return $TableCount
}
