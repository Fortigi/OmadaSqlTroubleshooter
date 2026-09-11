function Get-SqlFragmentDescendant {
    <#
    .SYNOPSIS
        Returns every ScriptDom fragment below a node, optionally filtered by type name.

    .DESCRIPTION
        ScriptDom's own way of walking a tree is to subclass TSqlFragmentVisitor, which needs a
        compiled type. Adding one would mean an Add-Type at import for a traversal that is a dozen
        lines, and it would put the rule predicates of issue #61 section 3.4 out of PowerShell's -
        and therefore out of Pester's - reach. So the tree is walked by reflection instead: every
        public property that is a fragment, or a collection of fragments, is a child.

        ScriptTokenStream is skipped by name. It is the flat token list of the WHOLE script, hung off
        every node, and following it would turn a tree walk into a walk of the entire script from
        each of its nodes.

        Nodes are returned in the order they are reached, and each node is returned once: identity is
        tracked by reference, so a tree that hangs the same node off two properties cannot produce a
        duplicate or a loop.

    .PARAMETER Fragment
        The node to walk. Null yields nothing.

    .PARAMETER TypeName
        Return only nodes whose type name is in this list, for example "NamedTableReference". The
        walk still descends through everything; only the output is filtered.

    .PARAMETER IncludeSelf
        Also consider $Fragment itself, not only its descendants.

    .OUTPUTS
        The matching [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment] nodes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment,
        [Parameter(Mandatory = $false)]
        [string[]]$TypeName,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeSelf
    )

    # No tracer preamble: this runs per validation pass over the user's query (issue #61 section 5).

    if ($null -eq $Fragment) {
        return @()
    }

    $Match = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)

    # An explicit stack rather than recursion. A deeply nested query would otherwise be limited by
    # PowerShell's recursion depth, and hitting that would turn a valid query into a failed pass.
    $Pending = [System.Collections.Generic.Stack[object]]::new()
    $Pending.Push([PSCustomObject]@{ Node = $Fragment; IsRoot = $true })

    $Wanted = $null
    if ($null -ne $TypeName -and $TypeName.Count -gt 0) {
        $Wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]$TypeName, [System.StringComparer]::OrdinalIgnoreCase)
    }

    while ($Pending.Count -gt 0) {
        $Current = $Pending.Pop()
        $Node = $Current.Node

        if ($null -eq $Node -or -not $Seen.Add($Node)) {
            continue
        }

        if (-not $Current.IsRoot -or $IncludeSelf) {
            if ($null -eq $Wanted -or $Wanted.Contains($Node.GetType().Name)) {
                $Match.Add($Node)
            }
        }

        # Reversed, so that pushing onto a stack still yields children in declaration order - which is
        # document order for every node ScriptDom builds, and what makes the diagnostics come out
        # sorted by position without a later sort.
        $Child = [System.Collections.Generic.List[object]]::new()

        foreach ($Property in $Node.GetType().GetProperties()) {
            if ($Property.Name -eq "ScriptTokenStream" -or -not $Property.CanRead -or $Property.GetIndexParameters().Length -gt 0) {
                continue
            }

            $Value = $null
            try {
                $Value = $Property.GetValue($Node)
            }
            catch {
                continue
            }

            if ($null -eq $Value) {
                continue
            }

            if ($Value -is [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment]) {
                $Child.Add($Value)
            }
            elseif ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable]) {
                foreach ($Item in $Value) {
                    if ($Item -is [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment]) {
                        $Child.Add($Item)
                    }
                }
            }
        }

        for ($Index = $Child.Count - 1; $Index -ge 0; $Index--) {
            $Pending.Push([PSCustomObject]@{ Node = $Child[$Index]; IsRoot = $false })
        }
    }

    return @($Match)
}
