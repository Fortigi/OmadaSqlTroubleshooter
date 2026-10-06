#Requires -Version 7.0
# Issue #166. Clear-DataGridColumnSelectionAnchor, and why it is a function at all.
#
# The anchor is the column a shift-click range-selects from. Select-DataGridColumnCells writes it;
# the GotFocus handler in Register-QueryResultGridHandler has to clear it when focus moves to another
# result, or a shift-click in the new grid ranges from a column in the old one. That clear used to be
# a bare `$Script:... = $null` inside a .GetNewClosure() scriptblock, which wrote into the closure's
# detached scope and left the real variable untouched - a no-op with no error and no log line.
#
# Select-DataGridColumnCells itself is NOT invoked here: its parameters are typed
# [System.Windows.Controls.DataGrid] and [System.Windows.Controls.DataGridColumn], which do not
# resolve in the headless lane. Dot-sourcing the file is still safe - a parameter's type constraint is
# resolved when the function is CALLED, not when it is defined - and that is the same arrangement
# Copy-DataGridToClipboard.Tests.ps1 relies on. The clear function is kept free of WPF types for
# exactly this reason, so the one thing that broke is the one thing that can be tested.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    # Defines Select-DataGridColumnCells and Clear-DataGridColumnSelectionAnchor. Only the latter is
    # called.
    . (Join-Path $PrivatePath -ChildPath "Select-DataGridColumnCells.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    $Script:SourcePath = Join-Path $PrivatePath -ChildPath "Select-DataGridColumnCells.ps1"

    $Private:ParseError = $null
    $Private:Token = $null
    $Script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($Script:SourcePath, [ref]$Private:Token, [ref]$Private:ParseError)
    $Script:ParseError = @($Private:ParseError)

    function Script:Get-AnchorAssignment {
        # Assignments TO the anchor, by what they assign. The AST rather than a regex over the file,
        # for a reason worth recording: the first version of this counted
        # '$Script:DataGridQueryResultColumnSelectionAnchor = $null' in the raw text and found two -
        # the real assignment, and the same line quoted inside the new function's own doc comment
        # explaining the bug. The test was counting documentation. An assignment node cannot be a
        # comment, so this asks the question that was actually meant.
        param([string]$RightHandSide)

        return @(
            $Script:Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Node.Left.VariablePath.UserPath -ieq "Script:DataGridQueryResultColumnSelectionAnchor"
                }, $true) |
                Where-Object { $_.Right.Extent.Text -ieq $RightHandSide }
        )
    }
}

Describe "Clear-DataGridColumnSelectionAnchor" {

    It "clears an anchor that was set" {
        # The whole contract: after this call a shift-click has nothing to range from.
        $Script:DataGridQueryResultColumnSelectionAnchor = "a column"

        Clear-DataGridColumnSelectionAnchor

        $Script:DataGridQueryResultColumnSelectionAnchor | Should -BeNullOrEmpty
    }

    It "is idempotent, because focus can move between results repeatedly" {
        # GotFocus fires on every focus change, including ones where no column was ever clicked.
        $Script:DataGridQueryResultColumnSelectionAnchor = $null

        { Clear-DataGridColumnSelectionAnchor } | Should -Not -Throw

        $Script:DataGridQueryResultColumnSelectionAnchor | Should -BeNullOrEmpty
    }

    It "takes no parameters, so nothing in its signature needs WPF to resolve" {
        # Not a style assertion. A [System.Windows.Controls.DataGrid] parameter here would make this
        # function uncallable in the headless lane - which is where the regression above is caught -
        # and would put the clear back out of reach of any test.
        $Private:Parameter = (Get-Command Clear-DataGridColumnSelectionAnchor).Parameters.Keys |
            Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }

        @($Private:Parameter).Count | Should -Be 0
    }
}

Describe "The anchor's writer and its clearer stay in one file" {
    # They are two halves of one piece of state. Splitting them is how the clear drifted out of scope
    # in the first place, so the pairing is asserted rather than assumed.
    #
    # Counted as AST assignment nodes, not as text - see Get-AnchorAssignment above for the trap that
    # prompted it.

    It "parses, so the counts below are over real assignments" {
        $Script:ParseError.Count | Should -Be 0
    }

    It "still writes the anchor from the column-selection paths" {
        # Both non-shift branches set it: a plain click and a Ctrl+click each become the new anchor.
        (Script:Get-AnchorAssignment -RightHandSide '$Column').Count | Should -Be 2
    }

    It "clears it in exactly one place, and that place is the function" {
        # A second assignment anywhere - especially back inside a closure, where it would be lost
        # again - is the defect returning.
        (Script:Get-AnchorAssignment -RightHandSide '$null').Count | Should -Be 1
    }
}
