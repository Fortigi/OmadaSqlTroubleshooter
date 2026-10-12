#Requires -Version 7.0
# Issue #159: Get-TreeViewItemLevel inverted its loop condition - `while ($null -eq $Parent)` - so
# the body never ran for a node that is actually in a tree, and the function returned 0 for every
# node whatever its depth. The only caller, Invoke-OnTreeViewItemShiftClick, switches on that value,
# so shift-clicking a table or a column in the SQL schema window always took the "0" branch and
# inserted the schema-level text.
#
# A node whose Parent was $null was worse than wrong: the module never sets Set-StrictMode, so
# $null.Parent yields $null, the condition stayed true and the loop never ended. The "no parent at
# all" test below is therefore a termination guard as much as a value assertion - against the old
# code it would have hung rather than failed.
#
# Named after the source FILE (Get-TreeViewLevel.ps1) rather than the function, because the psake
# Test task maps <Name>.Tests.ps1 onto a changed <Name>.ps1 (build/psakeBuild.ps1:158-168). Named
# after the function, this suite would be skipped on exactly the pull requests that touch it.

BeforeAll {
    # The function's stop condition names [System.Windows.Controls.TreeView]. A plain pwsh host does
    # not resolve that type on its own, and an unresolved type literal throws inside the function's
    # own catch - which returns $null, not an error, and every assertion below would then be reading
    # a swallowed failure rather than a level. Mirrors the Add-Type in Update-QueryList.Tests.ps1.
    Add-Type -AssemblyName PresentationFramework

    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-TreeViewLevel.ps1")
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    # A stand-in for the schema tree's nodes: the function reads nothing but .Parent, so plain objects
    # exercise the real walk while keeping the suite out of WPF's STA requirement - the same approach
    # Update-SqlSchemaTreeFilter.Tests.ps1 takes with Header/Items.
    #
    # The chain terminates in $null. In the running application it terminates in the TreeView, which
    # the function's `-isnot [TreeView]` test stops on; that terminator cannot be built here, because
    # constructing a WPF control needs an STA thread and PowerShell 7 is MTA. Both terminators stop
    # the same loop on the same iteration, so the depths asserted below are the depths the real tree
    # produces - see the pull request, which says plainly which half this suite does not prove.
    function script:New-TreeNodeChain {
        param([int]$Depth)

        $Node = $null
        foreach ($Index in 0..$Depth) {
            $Node = [PSCustomObject]@{ Header = "level$Index"; Parent = $Node }
        }

        return $Node
    }
}

Describe "Get-TreeViewItemLevel" {

    It "reports a top-level node as level 0" {
        # The data connection / schema level, depending on where in the tree you are: the node whose
        # parent is the TreeView itself.
        Get-TreeViewItemLevel -TreeViewItem (New-TreeNodeChain -Depth 0) | Should -Be 0
    }

    It "reports a child as level 1" {
        # Before the fix this came back as 0, which is why shift-clicking a table inserted the
        # schema-level "<name>." instead of the table text.
        Get-TreeViewItemLevel -TreeViewItem (New-TreeNodeChain -Depth 1) | Should -Be 1
    }

    It "reports a grandchild as level 2" {
        # The column level, whose shift-click branch produces ".<column>" or " <column>,".
        Get-TreeViewItemLevel -TreeViewItem (New-TreeNodeChain -Depth 2) | Should -Be 2
    }

    It "keeps counting past the levels the caller switches on" {
        # The switch handles 0, 1 and 2 and has a default; the function itself must not cap, or a
        # deeper tree would silently fold into one of the handled branches.
        Get-TreeViewItemLevel -TreeViewItem (New-TreeNodeChain -Depth 4) | Should -Be 4
    }

    It "returns 0 for a node with no parent at all, rather than never returning" {
        # The old loop spun forever here. This test passing at all is the assertion; the value is the
        # lesser half of it.
        $Orphan = [PSCustomObject]@{ Header = "orphan"; Parent = $null }

        Get-TreeViewItemLevel -TreeViewItem $Orphan | Should -Be 0
    }

    It "does not carry the inverted condition that made every node level 0" {
        # Guards the specific defect rather than only its symptoms: `$null -eq $Parent` as a loop
        # condition is the inversion, and it reads almost identically to the correct form.
        $Source = Get-Content -Path (Join-Path $PrivatePath -ChildPath "Get-TreeViewLevel.ps1") -Raw

        $Source | Should -Not -Match 'while\s*\(\s*\$null\s+-eq\s+\$Parent\s*\)'
        $Source | Should -Match 'while\s*\(\s*\$null\s+-ne\s+\$Parent'
    }
}
