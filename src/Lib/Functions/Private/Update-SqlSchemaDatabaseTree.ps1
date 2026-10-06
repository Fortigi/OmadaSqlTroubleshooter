function Get-SqlSchemaDatabaseNode {
    <#
    .SYNOPSIS
        Finds the schema tree's database node for a data connection DoId, or $null.

    .DESCRIPTION
        The top level of the tree is one node per data connection (issue #158), each carrying its
        DoId on .Tag. A response arrives for a DoId, not for a position, so this is how the
        completion finds the node to populate - the dropdown may have been re-sorted, or another
        database may have loaded, since the request was issued.

    .PARAMETER DataConnectionDoId
        The DoId to look for.

    .OUTPUTS
        The TreeViewItem, or $null.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DataConnectionDoId
    )

    # No tracer preamble: the node headers name the tenant's databases (issue #61 section 5).

    if ($null -eq $Script:TreeViewSqlSchema -or [string]::IsNullOrWhiteSpace($DataConnectionDoId)) {
        return $null
    }

    foreach ($Node in @($Script:TreeViewSqlSchema.Items)) {
        if ($null -ne $Node.Tag -and [string]$Node.Tag.DoId -eq $DataConnectionDoId) {
            return $Node
        }
    }

    return $null
}

function Update-SqlSchemaDatabaseTree {
    <#
    .SYNOPSIS
        Reconciles the schema tree's top level against the data connection dropdown: one node per
        connection.

    .DESCRIPTION
        Issue #158 criterion 1. The tree used to be schema -> table -> column for the selected
        connection alone, so the window could only ever describe one database; a query that names
        another one (issue #152) was unusable unless the user knew that database by heart.

        RECONCILES rather than rebuilds, and that is the whole point: a node whose schema is already
        loaded keeps its children, so this can run on every schema response without throwing away
        what the user has expanded, and without re-fetching anything. Nodes for connections that have
        disappeared from the dropdown are removed - which is also how issue #165's connection filter
        prunes the tree, without a second definition of which databases exist.

        THIS FUNCTION STILL FETCHES NOTHING. It builds the level and marks the active connection as
        already requested; every request belongs to somebody else. That is what keeps opening the
        window free, and it is asserted by SqlSchemaDatabaseTree.Tests.ps1.

        WHAT CHANGED IN #165 IS WHO FILLS THE NODES. This comment used to say, in capitals, that lazy
        loading was the design rather than an optimisation - and gave the reason: before issue #40 a
        fetch blocked the UI thread, so N connections meant N sequential freezes and loading them all
        was simply not available. Since #40 the fetch goes to a worker and is cached per pool, so
        Start-SqlSchemaPreload asks for every connection's schema as soon as the connection list is
        known, and a node is normally populated before the user ever clicks it.

        Invoke-SqlSchemaDatabaseNodeExpanded below is therefore no longer the usual path, but it is not
        dead code: the preload is skipped entirely when background requests are unavailable - see the
        eligibility gate there - and the on-expand fetch is what the window falls back to. The
        placeholder child stays for the same reason, plus one more: a node whose response has not landed
        yet still needs something to expand.

        The active connection's node is expanded and is populated by Complete-SqlSchemaRetrieval from
        the response the window already fetches.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        if ($null -eq $Script:TreeViewSqlSchema) {
            "Sql schema tree is not available, skip building the database level" | Write-LogOutput -LogType DEBUG
            return
        }

        # NOT wrapped in @(): the function returns its array through the ", $array" idiom so that an
        # empty or single-entry result survives the pipeline, and wrapping it again nests the array
        # one level deeper - which turns every .DoId below into an array of DoIds.
        #
        # -NoRefresh because this runs on the UI thread from a request completion, and a synchronous
        # tenant refresh hidden inside a tree rebuild would block the window. Nothing is lost by it:
        # Complete-DataConnectionListUpdate calls this again as soon as the list does arrive.
        $Private:Reference = Get-DataConnectionReferenceList -OptionList (Get-DataConnectionOptionText -NoRefresh)
        if ($Private:Reference.Count -eq 0) {
            "The data connection list is empty; leaving the schema tree as it is." | Write-LogOutput -LogType DEBUG
            return
        }

        $Private:ActiveDoId = [string]$Script:AppConfig.CurrentDataConnection.DoId

        # Drop nodes whose connection is gone, so a tenant that removed a data connection does not
        # keep offering it. Taken off a snapshot because the collection is modified in the loop.
        foreach ($Node in @($Script:TreeViewSqlSchema.Items)) {
            if ($null -eq $Node.Tag -or [string]$Node.Tag.DoId -notin @($Private:Reference.DoId)) {
                $Script:TreeViewSqlSchema.Items.Remove($Node)
            }
        }

        foreach ($Private:Connection in $Private:Reference) {
            if ($null -ne (Get-SqlSchemaDatabaseNode -DataConnectionDoId $Private:Connection.DoId)) {
                # Already on the tree. Leaving it alone is what preserves a loaded subtree and the
                # user's expansion state.
                continue
            }

            $Private:IsActive = ([string]$Private:Connection.DoId -eq $Private:ActiveDoId)

            # Loaded/Requested are declared in the constructor, not assigned later: a PSCustomObject
            # throws when given a property it was not built with.
            #
            # Requested starts $true for the active connection because its schema is already being
            # fetched by the normal path - without that, expanding it would dispatch a second,
            # duplicate request for the database the window is loading anyway.
            $Private:Tag = [PSCustomObject]@{
                DoId      = $Private:Connection.DoId
                Name      = $Private:Connection.Name
                Loaded    = $false
                Requested = $Private:IsActive
            }

            $Private:Node = New-SqlSchemaTreeItem -Header $Private:Connection.Name -FontSize 14 -Tag $Private:Tag

            # A node with no children has no expander arrow, so there would be nothing to click to
            # load it. The placeholder is replaced wholesale by Add-SqlSchemaTreeNode.
            $Private:Node.Items.Add((New-SqlSchemaTreeItem -Header "Loading..." -FontSize 12)) | Out-Null

            # Expanded BEFORE the handler is attached, so expanding the active node cannot re-enter
            # the fetch that is populating it. The Requested flag above is the second guard, for a
            # WPF build that raises Expanded only once the item is in the visual tree.
            if ($Private:IsActive) {
                $Private:Node.IsExpanded = $true
            }

            # A bare scriptblock calling a named function, never .GetNewClosure(): a closure created
            # in a Dispatcher callback loses the module's command table.
            #
            # The parameters are NOT called Sender/EventArgs - those are automatic variables, and
            # assigning to them is what PSAvoidAssignmentToAutomaticVariable objects to. Both are
            # declared, because a WPF handler is invoked with (sender, args) positionally and a
            # single declared parameter would bind the SENDER.
            $Private:Node.Add_Expanded({
                    param ($NodeSender, $NodeEventArgs)
                    Invoke-SqlSchemaDatabaseNodeExpanded -Sender $NodeSender -EventArgs $NodeEventArgs
                })

            $Script:TreeViewSqlSchema.Items.Add($Private:Node) | Out-Null
        }

        "Sql schema tree database level: {0} data connection(s)" -f $Private:Reference.Count | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Invoke-SqlSchemaDatabaseNodeExpanded {
    <#
    .SYNOPSIS
        Fetches a database's schema the first time its node is expanded.

    .DESCRIPTION
        The lazy half of issue #158 criterion 1. Its own function rather than a closure in
        Update-SqlSchemaDatabaseTree, for the reason the repository has hit before: a scriptblock
        created with .GetNewClosure() inside a Dispatcher callback loses the module's command table,
        so the handler is a bare scriptblock that calls a named function.

        Does nothing for a node that is already loaded or already asked, which is what keeps a
        collapse-and-expand from costing a second round trip, and what stops the active node from
        re-entering the fetch that is populating it.

    .PARAMETER Sender
        The database TreeViewItem that was expanded.

    .PARAMETER EventArgs
        The routed event arguments. Handled is set so an inner schema node expanding does not run
        this again for its database ancestor.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Sender', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'EventArgs', Justification = 'The use of the variable is on purpose')]
    param (
        $Sender,
        $EventArgs
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if ($null -eq $Sender -or $null -eq $Sender.Tag) {
            return
        }

        # Expanded bubbles: a schema node opening inside this database would otherwise run this
        # handler again for the database node above it.
        if ($null -ne $EventArgs) {
            $EventArgs.Handled = $true
        }

        if ($Sender.Tag.Loaded -or $Sender.Tag.Requested) {
            "Schema for data connection '{0}' is already loaded or requested." -f $Sender.Tag.Name | Write-LogOutput -LogType DEBUG
            return
        }

        $Sender.Tag.Requested = $true

        "Expanding data connection '{0}': retrieving its schema." -f $Sender.Tag.Name | Write-LogOutput -LogType DEBUG
        Get-SqlSchemaObject -DataConnectionDoId $Sender.Tag.DoId -DataConnectionName $Sender.Tag.Name
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
