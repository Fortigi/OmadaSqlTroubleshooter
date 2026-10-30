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

        THE SET IS BUILT WITH THE DEFAULT COMPARER, AND THAT IS DELIBERATE. ScriptDom's fragments
        inherit Equals and GetHashCode from System.Object without overriding either, so the default
        comparer already compares by reference - which is exactly what is wanted here. Naming
        ReferenceEqualityComparer explicitly would say the same thing and cost the feature its
        minimum supported runtime: that type arrived in .NET 5, and this module declares PowerShell
        7.0, which runs on .NET Core 3.1. Get-SqlFragmentDescendant.Tests.ps1 asserts the inheritance
        this depends on, so a future ScriptDom that did override them fails a test rather than
        silently merging two distinct nodes.

        COST (issue #185). The walk runs on every idle pause in the editor, several dozen times per
        validation, so two things that do not change the result are done once rather than per node:

          * The properties that can hold a child are resolved once per fragment TYPE, through
            Get-SqlFragmentChildProperty. A property whose declared type can never hold a fragment -
            an int, a string, an enum, most of what a node carries - is never read. Reading it could
            not have produced a child, so the result is the same; the reflection is what is saved.
          * Within Use-SqlFragmentWalkCache, one walk answers for every node it reaches, so the
            repeated walks of one validation run - from the root and from each query specification
            inside it - cost one walk in total. Outside that scope nothing is remembered, because a
            fragment's tree is only known not to change for as long as the caller holds it.

        HOW ONE WALK ANSWERS FOR A SUBTREE. The walk is a pre-order depth-first walk, so the
        descendants of any node it reaches are exactly the contiguous run of the list between that
        node and the end of its subtree. The walk records where each node's run starts and ends, and
        a later request for any node inside it is a slice of the list rather than a second walk.

        A slice is exact as long as no node inside a subtree was first reached from OUTSIDE it - the
        one case where a fresh walk from inside would reach a node the slice does not hold. ScriptDom
        does hang nodes off more than one property: every SchemaObjectName returns the same
        Identifier objects from Identifiers and again from BaseIdentifier and SchemaIdentifier. That
        sharing is between properties of the SAME parent, so the second reach finds a node already
        inside that parent's subtree, and every slice stays exact. Any other repeat - a node reached
        again from a parent whose subtree it was not first reached in - means a slice could be wrong,
        so such a walk registers nothing and every request for its nodes walks for real, as it did
        before the cache existed.

        The walk itself stays in this one function on purpose: it is the per-node loop, and a
        PowerShell function call per node costs more than the work it would wrap. Everything that
        runs once per request - the cache lookup, registering a walk, filtering by type - is in the
        helpers below.

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

    $Known = Get-SqlFragmentCachedDescendant -Fragment $Fragment
    if ($null -ne $Known) {
        return (Select-SqlFragmentByType -Fragment $Fragment -Descendant $Known -TypeName $TypeName -IncludeSelf:$IncludeSelf)
    }

    $FragmentType = [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment]
    $EnumerableType = [System.Collections.IEnumerable]
    $PropertyByType = $Script:SqlFragmentChildPropertyByType

    $Result = [System.Collections.Generic.List[object]]::new()

    # Start doubles as the "seen" set: a node is in it from the moment it is reached. The root is
    # entered at -1, ahead of the list it does not belong to.
    $Start = [System.Collections.Generic.Dictionary[object, int]]::new()
    $End = [System.Collections.Generic.Dictionary[object, int]]::new()
    $Start[$Fragment] = -1
    $Shared = $false

    # Three stacks in step rather than one stack of wrapper objects: an allocation per node is what
    # this walk is trying not to pay. IsExit marks the entry popped once a node's whole subtree has
    # been reached; ParentStart is where the node that pushed an entry sits in the list, which is
    # what tells a harmless repeat from one that would make a slice wrong.
    $Pending = [System.Collections.Generic.Stack[object]]::new()
    $IsExit = [System.Collections.Generic.Stack[bool]]::new()
    $ParentStart = [System.Collections.Generic.Stack[int]]::new()
    $Child = [System.Collections.Generic.List[object]]::new()

    $Pending.Push($Fragment)
    $IsExit.Push($true)
    $ParentStart.Push(-1)
    $Node = $Fragment
    $NodeStart = -1

    while ($null -ne $Node) {
        $Child.Clear()

        $Property = $null
        if (-not $PropertyByType.TryGetValue($Node.GetType(), [ref]$Property)) {
            $Property = Get-SqlFragmentChildProperty -Type $Node.GetType()
        }

        foreach ($Accessor in $Property) {
            try {
                $Value = $Accessor.GetValue($Node)
            }
            catch {
                continue
            }

            # Null is neither, so it needs no test of its own. A string is enumerable, but its
            # characters are never fragments, so it adds nothing either.
            if ($Value -is $FragmentType) {
                $Child.Add($Value)
            }
            elseif ($Value -is $EnumerableType) {
                foreach ($Item in $Value) {
                    if ($Item -is $FragmentType) {
                        $Child.Add($Item)
                    }
                }
            }
        }

        # Pushed in reverse so they pop in declaration order, which is what keeps the output in
        # document order.
        for ($Index = $Child.Count - 1; $Index -ge 0; $Index--) {
            $Pending.Push($Child[$Index])
            $IsExit.Push($false)
            $ParentStart.Push($NodeStart)
        }

        $Node = $null
        while ($Pending.Count -gt 0) {
            $Candidate = $Pending.Pop()
            $PushedBy = $ParentStart.Pop()

            if ($IsExit.Pop()) {
                $End[$Candidate] = $Result.Count - 1
                continue
            }

            # Reached before? The parent that pushed this entry is still open, so everything reached
            # since it started is inside its subtree; a node first reached before that is shared with
            # some other part of the tree.
            $Reached = 0
            if ($Start.TryGetValue($Candidate, [ref]$Reached)) {
                $Shared = $Shared -or ($Reached -le $PushedBy)
                continue
            }

            $NodeStart = $Result.Count
            $Start[$Candidate] = $NodeStart
            $Result.Add($Candidate)
            $Pending.Push($Candidate)
            $IsExit.Push($true)
            $ParentStart.Push($PushedBy)
            $Node = $Candidate
            break
        }
    }

    Register-SqlFragmentWalk -Fragment $Fragment -Descendant $Result -Start $Start -End $End -Shared $Shared

    return (Select-SqlFragmentByType -Fragment $Fragment -Descendant $Result -TypeName $TypeName -IncludeSelf:$IncludeSelf)
}

# Resolved per fragment type and kept for the life of the process - see Get-SqlFragmentChildProperty.
# Created here rather than on first use so the walk above needs no test for it on every call.
$Script:SqlFragmentChildPropertyByType = [System.Collections.Generic.Dictionary[type, System.Reflection.PropertyInfo[]]]::new()

function Select-SqlFragmentByType {
    <#
    .SYNOPSIS
        Applies Get-SqlFragmentDescendant's -TypeName and -IncludeSelf to a walked list.

    .PARAMETER Fragment
        The node that was walked.

    .PARAMETER Descendant
        Its descendants, in walk order. Not modified: it may be shared with the walk cache.

    .PARAMETER TypeName
        Type names to keep, case-insensitively. Empty keeps everything.

    .PARAMETER IncludeSelf
        Also consider $Fragment itself.

    .OUTPUTS
        [object[]] the matching nodes, $Fragment first when it matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Fragment,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Descendant,
        [Parameter(Mandatory = $false)]
        [string[]]$TypeName,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeSelf
    )

    $Wanted = $null
    if ($null -ne $TypeName -and $TypeName.Count -gt 0) {
        $Wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]$TypeName, [System.StringComparer]::OrdinalIgnoreCase)
    }

    $Match = [System.Collections.Generic.List[object]]::new()

    if ($IncludeSelf -and ($null -eq $Wanted -or $Wanted.Contains($Fragment.GetType().Name))) {
        $Match.Add($Fragment)
    }

    if ($null -eq $Wanted) {
        $Match.AddRange($Descendant)
        return @($Match)
    }

    foreach ($Node in $Descendant) {
        if ($Wanted.Contains($Node.GetType().Name)) {
            $Match.Add($Node)
        }
    }

    return @($Match)
}

function Get-SqlFragmentCachedDescendant {
    <#
    .SYNOPSIS
        Returns a node's descendants from the walk cache, or $null when they have to be walked.

    .DESCRIPTION
        Two ways to answer: the node was itself walked, or it was reached by a walk that can answer
        for it by slicing (see Get-SqlFragmentDescendant). A slice is kept once taken, so asking for
        the same node again costs a lookup.

    .PARAMETER Fragment
        The node whose descendants are wanted.

    .OUTPUTS
        [System.Collections.Generic.List[object]] shared with the cache, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Fragment
    )

    $Cache = $Script:SqlFragmentWalkCache
    if ($null -eq $Cache) {
        return $null
    }

    $Known = $null
    if ($Cache.Result.TryGetValue($Fragment, [ref]$Known)) {
        return , $Known
    }

    $Walk = $null
    if (-not $Cache.Owner.TryGetValue($Fragment, [ref]$Walk)) {
        return $null
    }

    $Begin = $Walk.Start[$Fragment]
    $Known = $Walk.List.GetRange($Begin + 1, $Walk.End[$Fragment] - $Begin)
    $Cache.Result[$Fragment] = $Known
    return , $Known
}

function Register-SqlFragmentWalk {
    <#
    .SYNOPSIS
        Records a finished walk in the walk cache, when one is active.

    .DESCRIPTION
        The walked node's own list is always kept. Every node the walk reached is registered as
        answerable by slicing only when the walk saw no harmful sharing - see
        Get-SqlFragmentDescendant for why that is the condition.

    .PARAMETER Fragment
        The node that was walked.

    .PARAMETER Descendant
        Everything the walk reached, in order.

    .PARAMETER Start
        node -> its position in Descendant.

    .PARAMETER End
        node -> the position of the last node of its subtree.

    .PARAMETER Shared
        Whether the walk met a node it could not answer for by slicing.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Fragment,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Descendant,
        [Parameter(Mandatory = $true)]
        $Start,
        [Parameter(Mandatory = $true)]
        $End,
        [Parameter(Mandatory = $true)]
        [bool]$Shared
    )

    $Cache = $Script:SqlFragmentWalkCache
    if ($null -eq $Cache) {
        return
    }

    $Cache.Result[$Fragment] = $Descendant

    if ($Shared) {
        return
    }

    $Walk = [PSCustomObject]@{
        List  = $Descendant
        Start = $Start
        End   = $End
    }
    foreach ($Reached in $Descendant) {
        $Cache.Owner[$Reached] = $Walk
    }
}

function Get-SqlFragmentChildProperty {
    <#
    .SYNOPSIS
        Returns the properties of a fragment type that can hold a child fragment.

    .DESCRIPTION
        A property can hold a child when its declared type is a fragment, is something a fragment can
        be assigned to (object, or an interface a fragment implements), or is a collection - the walk
        then looks at each item. Everything else (value types, strings, enums, sealed non-fragment
        classes) can never hold a fragment, so reading it could not add a child and it is left out.

        ScriptTokenStream is excluded by name, as it always was: it is the flat token list of the
        WHOLE script, hung off every node. Indexers and write-only properties are excluded because
        they cannot be read without arguments.

        Resolved once per type and kept for the life of the process: a type's properties do not
        change, and the same few dozen fragment types make up every query.

    .PARAMETER Type
        The runtime type of a fragment.

    .OUTPUTS
        [System.Reflection.PropertyInfo[]]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [type]$Type
    )

    $Known = $null
    if ($Script:SqlFragmentChildPropertyByType.TryGetValue($Type, [ref]$Known)) {
        return , $Known
    }

    $FragmentType = [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment]
    $Selected = [System.Collections.Generic.List[System.Reflection.PropertyInfo]]::new()

    foreach ($Property in $Type.GetProperties()) {
        if ($Property.Name -eq "ScriptTokenStream" -or -not $Property.CanRead -or $Property.GetIndexParameters().Length -gt 0) {
            continue
        }

        $PropertyType = $Property.PropertyType
        $CanHoldFragment = $FragmentType.IsAssignableFrom($PropertyType) -or $PropertyType.IsAssignableFrom($FragmentType)
        $IsCollection = $PropertyType -ne [string] -and [System.Collections.IEnumerable].IsAssignableFrom($PropertyType)

        if ($CanHoldFragment -or $IsCollection) {
            $Selected.Add($Property)
        }
    }

    $Known = $Selected.ToArray()
    $Script:SqlFragmentChildPropertyByType[$Type] = $Known

    return , $Known
}

function Use-SqlFragmentWalkCache {
    <#
    .SYNOPSIS
        Runs a script block with the per-node walk cache switched on, and switches it off afterwards.

    .DESCRIPTION
        One validation run walks the same tree dozens of times: the schema pass from the root four
        times and per query specification twice, the Omada pass from the root again per rule. Inside
        this scope each node's descendant list is computed once and then served from memory (issue
        #185).

        The cache is keyed by node REFERENCE (fragments do not override Equals/GetHashCode - see
        Get-SqlFragmentDescendant.Tests.ps1) and lives only for the duration of the script block, so
        it can never serve a list for a tree the caller has since replaced. A nested call reuses the
        outer scope's cache rather than starting a second one, and leaves it in place on the way out.

    .PARAMETER ScriptBlock
        The work to run. Its output is returned unchanged.

    .OUTPUTS
        Whatever the script block returns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [scriptblock]$ScriptBlock
    )

    if ($null -ne $Script:SqlFragmentWalkCache) {
        return (& $ScriptBlock)
    }

    $Script:SqlFragmentWalkCache = [PSCustomObject]@{
        # node -> the list already handed out for it
        Result = [System.Collections.Generic.Dictionary[object, System.Collections.Generic.List[object]]]::new()
        # node -> the walk that reached it, when that walk can answer for it by slicing
        Owner  = [System.Collections.Generic.Dictionary[object, object]]::new()
    }
    try {
        return (& $ScriptBlock)
    }
    finally {
        $Script:SqlFragmentWalkCache = $null
    }
}
