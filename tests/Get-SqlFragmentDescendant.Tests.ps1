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
