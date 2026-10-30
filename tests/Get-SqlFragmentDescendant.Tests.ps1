#Requires -Version 7.0
# Tests for the AST walk the three validation passes of issue #61 share.
#
# The first Context is the one that matters beyond this file. The walk de-duplicates nodes with a
# plain HashSet[object], which is correct ONLY because ScriptDom's fragments inherit Equals and
# GetHashCode from System.Object - making the default comparer a reference comparer. Saying that
# explicitly with ReferenceEqualityComparer would be clearer and would also break the module's
# declared minimum runtime: that type arrived in .NET 5, and PowerShell 7.0 runs on .NET Core 3.1.
# So the assumption is asserted here instead, and a future ScriptDom package that overrode either
# method fails a test rather than silently merging two distinct nodes into one.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptFragment.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentDescendant.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentMarker.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    $script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath

    function Get-TestFragment {
        param([string]$SqlText)
        return (Get-SqlScriptFragment -SqlText $SqlText).Fragment
    }

    # The walk exactly as it was before issue #185 made it cheaper, kept here as the oracle the new one
    # is compared against. Not the module's code: a copy, so that changing the module cannot change
    # what "the same result" means.
    function Get-SqlFragmentDescendantReference {
        param($Fragment, [string[]]$TypeName, [switch]$IncludeSelf)

        if ($null -eq $Fragment) {
            return @()
        }

        $Match = [System.Collections.Generic.List[object]]::new()
        $Seen = [System.Collections.Generic.HashSet[object]]::new()

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

    # Same nodes, same order, compared by REFERENCE - two distinct nodes describing the same text must
    # not count as equal.
    #
    # Nulls are dropped first: an empty result passed as an argument arrives as $null, and @($null) is
    # a one-element list - which would make "nothing" and "nothing" compare unequal depending only on
    # how the caller wrapped them.
    function Test-SameNodeList {
        param($Expected, $Actual)
        $Expected = @($Expected | Where-Object { $null -ne $_ })
        $Actual = @($Actual | Where-Object { $null -ne $_ })
        if ($Expected.Count -ne $Actual.Count) {
            return $false
        }
        for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
            if (-not [object]::ReferenceEquals($Expected[$Index], $Actual[$Index])) {
                return $false
            }
        }
        return $true
    }

    $script:WalkCorpus = @(
        "SELECT 1 AS a"
        "SELECT p.Id FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id WHERE p.Deleted = 0 ORDER BY p.Id"
        "WITH c1 AS (SELECT i.Id FROM dbo.Person i WHERE i.Id IN (SELECT x.Id FROM dbo.Other x WHERE x.Ref = (SELECT TOP 1 y.Id FROM dbo.Third y))), c2 AS (SELECT Id FROM c1) SELECT c1.Id FROM c1 JOIN c2 ON c2.Id = c1.Id WHERE EXISTS (SELECT 1 FROM c2 WHERE c2.Id = c1.Id)"
        "SELECT Id INTO #Temp FROM dbo.Person; SELECT * FROM #Temp; DROP TABLE #Temp;"
        "SELECT j.a, CASE WHEN p.x > 1 THEN 'y' ELSE 'n' END AS z, COUNT(*) OVER (PARTITION BY p.k) AS n FROM dbo.Person p CROSS APPLY OPENJSON(p.Payload) WITH (a int) AS j GROUP BY j.a, p.x, p.k HAVING COUNT(*) > 1"
        "UPDATE dbo.Person SET DisplayName = 'x' WHERE Id = 1; DELETE FROM dbo.Person WHERE Id = 2; INSERT INTO dbo.Person (Id) VALUES (3)"
        "SELECT a, FROM dbo.Person"
    )
}

Describe 'The identity assumption the walk depends on' -Tag 'Unit' {

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    It 'Should leave <Method> inherited from System.Object on TSqlFragment' -ForEach @(
        @{ Method = 'Equals' }
        @{ Method = 'GetHashCode' }
    ) {
        $FragmentType = [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlFragment]
        $Declaring = if ($Method -eq 'Equals') {
            $FragmentType.GetMethod("Equals", [type[]]@([object])).DeclaringType
        }
        else {
            $FragmentType.GetMethod("GetHashCode").DeclaringType
        }

        $Declaring.FullName | Should -Be "System.Object" -Because "the walk's HashSet relies on the default comparer being a reference comparer"
    }

    It 'Should treat two identical fragments parsed separately as different nodes' {
        # The assumption, stated as behaviour rather than as reflection: the same text parsed twice
        # produces two nodes, and a set must hold both.
        $First = Get-TestFragment "SELECT 1 AS a"
        $Second = Get-TestFragment "SELECT 1 AS a"

        $Set = [System.Collections.Generic.HashSet[object]]::new()
        $Set.Add($First) | Should -BeTrue
        $Set.Add($Second) | Should -BeTrue -Because "two distinct nodes must never collapse into one"
        $Set.Add($First) | Should -BeFalse -Because "the same node must not be added twice"
    }

    It 'Should not name a type that the declared minimum PowerShell version lacks' {
        # ReferenceEqualityComparer is .NET 5+; the manifest declares PowerShell 7.0, which is
        # .NET Core 3.1. Asserted on the source so the shortcut cannot be reintroduced as a tidy-up.
        foreach ($File in @("Get-SqlFragmentDescendant.ps1", "Get-SqlSchemaDiagnostic.ps1")) {
            $Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\$File") -Raw
            $Source | Should -Not -Match '\[System\.Collections\.Generic\.ReferenceEqualityComparer\]' -Because "$File must run on PowerShell 7.0"
        }
    }
}

Describe 'Get-SqlFragmentDescendant' -Tag 'Unit' {

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    It 'Should return nothing for a null fragment' {
        @(Get-SqlFragmentDescendant -Fragment $null).Count | Should -Be 0
    }

    It 'Should find nodes by type name anywhere in the tree' {
        $Fragment = Get-TestFragment "SELECT p.Id FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id"

        @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "NamedTableReference").Count | Should -Be 2
    }

    It 'Should exclude the root unless asked for it' {
        $Fragment = Get-TestFragment "SELECT 1 AS a"

        @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "TSqlScript").Count | Should -Be 0
        @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "TSqlScript" -IncludeSelf).Count | Should -Be 1
    }

    It 'Should match type names case-insensitively' {
        $Fragment = Get-TestFragment "SELECT 1 AS a FROM dbo.Person"

        @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "namedtablereference").Count | Should -Be 1
    }

    It 'Should return nodes in document order' {
        $Fragment = Get-TestFragment "SELECT p.Id FROM dbo.Alpha p JOIN dbo.Beta b ON b.Id = p.Id"

        @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "NamedTableReference" |
                ForEach-Object { $_.SchemaObject.BaseIdentifier.Value }) | Should -Be @("Alpha", "Beta")
    }

    It 'Should not follow the script token stream' {
        # It is the flat token list of the WHOLE script hung off every node; following it would turn a
        # tree walk into a walk of the entire script from each of its nodes.
        $Fragment = Get-TestFragment "SELECT 1 AS a"
        $Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\Get-SqlFragmentDescendant.ps1") -Raw

        $Source | Should -Match 'ScriptTokenStream'
        @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "TSqlParserToken").Count | Should -Be 0
    }

    It 'Should survive a deeply nested query without running out of stack' {
        # An explicit stack rather than recursion: hitting PowerShell's recursion depth would turn a
        # valid query into a failed pass.
        $Query = "SELECT x0.n AS n FROM (SELECT 1 AS n) x0"
        for ($Index = 1; $Index -le 60; $Index++) {
            $Query = "SELECT x$Index.n AS n FROM ($Query) x$Index"
        }

        { Get-SqlFragmentDescendant -Fragment (Get-TestFragment $Query) -TypeName "QuerySpecification" } | Should -Not -Throw
    }
}

Describe 'Get-SqlFragmentMarker' -Tag 'Unit' {

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    It 'Should span the whole fragment by default' {
        $Fragment = Get-TestFragment "SELECT COUNT(*) FROM dbo.Person"
        $Element = @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "SelectScalarExpression")[0]

        $Marker = Get-SqlFragmentMarker -Fragment $Element
        $Marker.Line | Should -Be 1
        $Marker.Column | Should -Be 8
        $Marker.EndColumn | Should -Be 16 -Because "'COUNT(*)' is eight characters wide"
    }

    It 'Should span only the keyword when asked' {
        $Fragment = Get-TestFragment "UPDATE dbo.Person SET DisplayName = 'x'"
        $Statement = @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "UpdateStatement")[0]

        $Marker = Get-SqlFragmentMarker -Fragment $Statement -KeywordOnly
        $Marker.Column | Should -Be 1
        $Marker.EndColumn | Should -Be 7 -Because "'UPDATE' is six characters wide"
    }

    It 'Should carry a multi-line fragment onto the line it ends on' {
        $Fragment = Get-TestFragment "SELECT`r`n  COUNT(*)`r`nFROM dbo.Person"
        $Element = @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "SelectScalarExpression")[0]

        $Marker = Get-SqlFragmentMarker -Fragment $Element
        $Marker.Line | Should -Be 2
        $Marker.EndLine | Should -Be 2
    }

    It 'Should return nothing for a null fragment' {
        Get-SqlFragmentMarker -Fragment $null | Should -BeNullOrEmpty
    }
}

Describe 'Get-SqlFragmentDescendant returns what it returned before issue #185' -Tag 'Unit' {
    # Issue #185 made the walk cheap - child properties resolved once per type, and within
    # Use-SqlFragmentWalkCache one walk answering for every node it reaches. Neither may change the
    # answer. These compare against the walk as it was, from EVERY node of every query, because the
    # cache answers a subtree by slicing and a wrong slice boundary would only show from inside.

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    It 'Should parse every query in the corpus but the deliberately broken one' {
        # A query that does not parse yields no tree, and every comparison below would then compare
        # nothing with nothing.
        for ($Index = 0; $Index -lt 6; $Index++) {
            @((Get-SqlScriptFragment -SqlText $script:WalkCorpus[$Index]).ParseError).Count | Should -Be 0 -Because $script:WalkCorpus[$Index]
        }
    }

    It 'Should return the same nodes in the same order from every node, without the cache: <_>' -ForEach @(0..6) {
        $Root = Get-TestFragment $script:WalkCorpus[$_]
        foreach ($Node in @($Root) + @(Get-SqlFragmentDescendantReference -Fragment $Root)) {
            Test-SameNodeList -Expected (Get-SqlFragmentDescendantReference -Fragment $Node) -Actual (Get-SqlFragmentDescendant -Fragment $Node) | Should -BeTrue
        }
    }

    It 'Should return the same nodes in the same order from every node, with the cache: <_>' -ForEach @(0..6) {
        $Root = Get-TestFragment $script:WalkCorpus[$_]
        $Nodes = @($Root) + @(Get-SqlFragmentDescendantReference -Fragment $Root)

        Use-SqlFragmentWalkCache {
            # The root first, the way the passes start - every later request is then a slice of it.
            foreach ($Node in $Nodes) {
                Test-SameNodeList -Expected (Get-SqlFragmentDescendantReference -Fragment $Node) -Actual (Get-SqlFragmentDescendant -Fragment $Node) | Should -BeTrue
            }
        }
    }

    It 'Should return the same nodes when the walks start deep and work outwards: <_>' -ForEach @(0..6) {
        # The opposite order: inner walks register first, and the root walk must not be served from
        # them.
        $Root = Get-TestFragment $script:WalkCorpus[$_]
        $Nodes = @($Root) + @(Get-SqlFragmentDescendantReference -Fragment $Root)
        [array]::Reverse($Nodes)

        Use-SqlFragmentWalkCache {
            foreach ($Node in $Nodes) {
                Test-SameNodeList -Expected (Get-SqlFragmentDescendantReference -Fragment $Node) -Actual (Get-SqlFragmentDescendant -Fragment $Node) | Should -BeTrue
            }
        }
    }

    It 'Should filter by <TypeName> and honour -IncludeSelf exactly as before' -ForEach @(
        @{ TypeName = 'QuerySpecification' }
        @{ TypeName = 'ColumnReferenceExpression' }
        @{ TypeName = 'NamedTableReference' }
        @{ TypeName = 'TSqlScript' }
    ) {
        $Root = Get-TestFragment $script:WalkCorpus[2]
        foreach ($Self in @($false, $true)) {
            $Expected = Get-SqlFragmentDescendantReference -Fragment $Root -TypeName $TypeName -IncludeSelf:$Self
            Test-SameNodeList -Expected $Expected -Actual (Get-SqlFragmentDescendant -Fragment $Root -TypeName $TypeName -IncludeSelf:$Self) | Should -BeTrue
            Use-SqlFragmentWalkCache {
                Test-SameNodeList -Expected $Expected -Actual (Get-SqlFragmentDescendant -Fragment $Root -TypeName $TypeName -IncludeSelf:$Self) | Should -BeTrue
            }
        }
    }

    It 'Should return the same nodes when one node hangs off two properties of the same parent' {
        # What ScriptDom itself does: SchemaObjectName returns the same Identifier from Identifiers and
        # again from BaseIdentifier. Harmless for slicing - the repeat is inside the parent's subtree -
        # so the cache stays on, and must still agree with the reference from every node.
        $Root = Get-TestFragment "SELECT p.Id FROM dbo.Person p WHERE p.Id = 1"
        $Comparison = @(Get-SqlFragmentDescendantReference -Fragment $Root -TypeName "BooleanComparisonExpression")[0]
        $Comparison.SecondExpression = $Comparison.FirstExpression

        $Nodes = @($Root) + @(Get-SqlFragmentDescendantReference -Fragment $Root)
        Use-SqlFragmentWalkCache {
            foreach ($Node in $Nodes) {
                $Actual = @(Get-SqlFragmentDescendant -Fragment $Node)
                Test-SameNodeList -Expected @(Get-SqlFragmentDescendantReference -Fragment $Node) -Actual $Actual | Should -BeTrue
                @($Actual | ForEach-Object { [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($_) } | Select-Object -Unique).Count | Should -Be $Actual.Count
            }
        }
    }

    It 'Should return the same nodes when one node hangs off two different parts of the tree' {
        # The case slicing cannot answer: the SELECT list's column also placed in the WHERE clause. A
        # fresh walk from the WHERE clause reaches it; a slice of the root walk would not, because the
        # root walk met it first in the SELECT list. The walk must notice and answer for real.
        $Root = Get-TestFragment "SELECT p.Id FROM dbo.Person p WHERE p.Other = 1"
        $Selected = @(Get-SqlFragmentDescendantReference -Fragment $Root -TypeName "SelectScalarExpression")[0]
        $Comparison = @(Get-SqlFragmentDescendantReference -Fragment $Root -TypeName "BooleanComparisonExpression")[0]
        $Comparison.FirstExpression = $Selected.Expression

        $Nodes = @($Root) + @(Get-SqlFragmentDescendantReference -Fragment $Root)
        Use-SqlFragmentWalkCache {
            foreach ($Node in $Nodes) {
                $Actual = @(Get-SqlFragmentDescendant -Fragment $Node)
                Test-SameNodeList -Expected @(Get-SqlFragmentDescendantReference -Fragment $Node) -Actual $Actual | Should -BeTrue
                @($Actual | ForEach-Object { [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($_) } | Select-Object -Unique).Count | Should -Be $Actual.Count
            }
        }

        Use-SqlFragmentWalkCache {
            $null = Get-SqlFragmentDescendant -Fragment $Root
            $Script:SqlFragmentWalkCache.Owner.Count | Should -Be 0 -Because "the root walk met the shared node twice and must not answer for its nodes by slicing"
        }
    }
}

Describe 'Use-SqlFragmentWalkCache' -Tag 'Unit' {

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    It 'Should return what the script block returns' {
        Use-SqlFragmentWalkCache { 42 } | Should -Be 42
    }

    It 'Should be active inside the block and gone after it' {
        $Script:SqlFragmentWalkCache | Should -BeNullOrEmpty
        Use-SqlFragmentWalkCache { $Script:SqlFragmentWalkCache | Should -Not -BeNullOrEmpty }
        $Script:SqlFragmentWalkCache | Should -BeNullOrEmpty -Because "a cache outliving the run could serve a tree the caller has since replaced"
    }

    It 'Should be gone after the block throws' {
        { Use-SqlFragmentWalkCache { throw "the pass failed" } } | Should -Throw
        $Script:SqlFragmentWalkCache | Should -BeNullOrEmpty
    }

    It 'Should reuse an outer cache rather than replacing it, and leave it in place' {
        Use-SqlFragmentWalkCache {
            $Outer = $Script:SqlFragmentWalkCache
            Use-SqlFragmentWalkCache { [object]::ReferenceEquals($Script:SqlFragmentWalkCache, $Outer) | Should -BeTrue }
            [object]::ReferenceEquals($Script:SqlFragmentWalkCache, $Outer) | Should -BeTrue
        }
    }

    It 'Should walk a tree once however many of its nodes are asked for' {
        $Root = Get-TestFragment $script:WalkCorpus[2]
        Use-SqlFragmentWalkCache {
            $null = Get-SqlFragmentDescendant -Fragment $Root
            $Walked = $Script:SqlFragmentWalkCache.Result.Count

            foreach ($Specification in @(Get-SqlFragmentDescendant -Fragment $Root -TypeName "QuerySpecification")) {
                $null = Get-SqlFragmentDescendant -Fragment $Specification -TypeName "ColumnReferenceExpression"
            }

            # Every later answer was a slice of the first walk, so every node is owned by it.
            @($Script:SqlFragmentWalkCache.Owner.Values | Select-Object -Unique).Count | Should -Be 1
            $Script:SqlFragmentWalkCache.Result.Count | Should -BeGreaterThan $Walked
        }
    }
}

Describe 'Get-SqlFragmentChildProperty' -Tag 'Unit' {

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    It 'Should leave out properties that can never hold a fragment' {
        $Name = @(Get-SqlFragmentChildProperty -Type ([Microsoft.SqlServer.TransactSql.ScriptDom.Identifier]) | ForEach-Object { $_.Name })

        $Name | Should -Not -Contain "Value" -Because "a string cannot hold a fragment"
        $Name | Should -Not -Contain "StartOffset" -Because "an int cannot hold a fragment"
        $Name | Should -Not -Contain "QuoteType" -Because "an enum cannot hold a fragment"
    }

    It 'Should keep fragment and collection properties' {
        $Name = @(Get-SqlFragmentChildProperty -Type ([Microsoft.SqlServer.TransactSql.ScriptDom.QuerySpecification]) | ForEach-Object { $_.Name })

        $Name | Should -Contain "FromClause"
        $Name | Should -Contain "SelectElements"
        $Name | Should -Contain "WhereClause"
    }

    It 'Should never follow the script token stream' {
        $Name = @(Get-SqlFragmentChildProperty -Type ([Microsoft.SqlServer.TransactSql.ScriptDom.TSqlScript]) | ForEach-Object { $_.Name })

        $Name | Should -Not -Contain "ScriptTokenStream"
    }

    It 'Should resolve a type once' {
        $Type = [Microsoft.SqlServer.TransactSql.ScriptDom.SelectStatement]
        $First = Get-SqlFragmentChildProperty -Type $Type

        [object]::ReferenceEquals($First, (Get-SqlFragmentChildProperty -Type $Type)) | Should -BeTrue
    }
}
