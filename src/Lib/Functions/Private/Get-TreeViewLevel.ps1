function Get-TreeViewItemLevel {
    [CmdLetBinding()]
    param (
        # Untyped on purpose (issue #159). The one caller passes a real TreeViewItem; the tests pass a
        # plain-object stand-in for the tree, the way Update-SqlSchemaTreeFilter.Tests.ps1 does. A
        # [System.Windows.Controls.TreeViewItem] annotation would put this function out of reach of
        # every headless test, because a WPF control cannot be constructed off an STA thread and
        # PowerShell 7 is MTA.
        $TreeViewItem
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $Level = 0
        $Parent = $TreeViewItem.Parent

        # Walk up to the TreeView, counting the TreeViewItems on the way. A top-level item's Parent IS
        # the TreeView, so it stops immediately and the item is level 0; its child is 1, and so on.
        #
        # Two things in this condition are the fix for issue #159, and both mattered:
        #
        #   * `$null -ne` rather than `$null -eq`. Inverted, the body never ran for a node that is in a
        #     tree - every node reported 0 - and for a node with no parent it never ended, because the
        #     module does not set Set-StrictMode, so $null.Parent is $null and the condition stayed
        #     true forever.
        #   * The stop is tested BEFORE the increment, and the increment is unconditional. The old body
        #     tested $Parent for TreeViewItem-ness and only then reassigned it, so even with the
        #     comparison the right way round the TreeView itself would have been walked into and a
        #     top-level item would have come back as 1.
        while ($null -ne $Parent -and $Parent -isnot [System.Windows.Controls.TreeView]) {
            $Level++
            $Parent = $Parent.Parent
        }

        return $Level
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}

