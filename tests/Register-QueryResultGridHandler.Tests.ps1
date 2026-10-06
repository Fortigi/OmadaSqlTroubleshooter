#Requires -Version 7.0
# Issue #166. The rule this file enforces, stated once: a scriptblock closed with .GetNewClosure()
# may not read or write a module $Script: VARIABLE.
#
# A closure runs in a detached dynamic module. Module FUNCTIONS resolve from it perfectly well, which
# is why the handlers in Register-QueryResultGridHandler.ps1 can call Write-LogOutput and
# Set-FocusedQueryResult; module VARIABLES do not, and read as $null. Measured on PowerShell 7.6.5
# with a minimal module: a bare scriptblock saw the variable, a .GetNewClosure() one saw nothing.
#
# That cost two defects with very different noise levels:
#
#   * the four copy shortcuts read $Script:DataGridQueryResultMenuItem* as $null and threw
#     "You cannot call a method on a null-valued expression" on .RaiseEvent() - the reported bug;
#   * the GotFocus handler's `$Script:DataGridQueryResultColumnSelectionAnchor = $null` wrote into the
#     closure's own scope, so the anchor was never cleared and a shift-click in a newly focused grid
#     ranged from a column in the previous one - no error, no log line, nothing to notice.
#
# ASSERTED BY PARSING, not by running. Nothing here imports the module or touches WPF: the handlers
# only exist once an ItemsControl has realised its grids, and System.Windows.Input.* does not resolve
# in the headless lane at all. What a real run would add - that a keystroke reaches the clipboard and
# that focus genuinely clears the anchor - is measured in QueryResultStackLayout.Sta.Tests.ps1, which
# raises real routed events in a pwsh -STA child and reports inconclusive where no GUI runtime exists.
#
# The AST is used rather than a regex over the text because the question is structural: is this
# variable reference INSIDE a closure body? A regex cannot answer that, and the file legitimately
# contains $Script: reads outside the closures.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:SourcePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Register-QueryResultGridHandler.ps1"
    $Script:SourceText = Get-Content -Path $Script:SourcePath -Raw

    $Private:ParseError = $null
    $Private:Token = $null
    $Script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($Script:SourcePath, [ref]$Private:Token, [ref]$Private:ParseError)
    $Script:ParseError = @($Private:ParseError)

    # Every scriptblock that is closed with .GetNewClosure(), i.e. the expression's target.
    $Script:ClosureBody = @(
        $Script:Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                "$($Node.Member.Value)" -eq "GetNewClosure"
            }, $true) |
            ForEach-Object { $_.Expression } |
            Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }
    )

    function Script:Get-ScriptScopedVariable {
        param($Body)

        return @(
            $Body.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Node.VariablePath.UserPath -imatch '^script:'
                }, $true)
        )
    }

    function Script:Get-CommandByName {
        param([string]$Name)

        return @(
            $Script:Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and
                    "$($Node.GetCommandName())" -eq $Name
                }, $true)
        )
    }
}

Describe "The source still parses" {
    It "has no parse errors, so every assertion below is about real structure" {
        $Script:ParseError.Count | Should -Be 0
    }
}

Describe "No closure in this file reads or writes a module variable" {

    It "still has closures to check, so a green run is not an empty one" {
        # If .GetNewClosure() were removed wholesale, every assertion below would pass vacuously. The
        # closures are still required: they are what gives each handler the $GridIndex of its own
        # iteration rather than the loop's last value.
        $Script:ClosureBody.Count | Should -BeGreaterThan 0
    }

    It "references no `$Script: variable inside any GetNewClosure body" {
        # THE regression test for issue #166, and for the whole class rather than the two instances
        # that were found. A failure here names the variable and the line, which is the information the
        # original bug report did not have.
        $Private:Offender = foreach ($Private:Body in $Script:ClosureBody) {
            foreach ($Private:Variable in (Script:Get-ScriptScopedVariable -Body $Private:Body)) {
                "{0} (line {1})" -f $Private:Variable.Extent.Text, $Private:Variable.Extent.StartLineNumber
            }
        }

        @($Private:Offender) -join ", " | Should -BeExactly ""
    }
}

Describe "The copy shortcuts call the copy function" {

    It "calls Copy-DataGridToClipboard once per shortcut" {
        # Ctrl+C, Ctrl+Shift+C, Ctrl+Shift+P, Ctrl+Shift+S.
        (Script:Get-CommandByName -Name "Copy-DataGridToClipboard").Count | Should -Be 4
    }

    It "passes each shortcut the arguments its menu item passes" {
        # The shortcuts and the context menu must not drift: these are the four argument shapes the
        # MenuItem Click handlers in MainFormTabContent.Elements.DataGridQueryResult.ps1 use.
        $Private:Invocation = @(
            Script:Get-CommandByName -Name "Copy-DataGridToClipboard" | ForEach-Object {
                ($_.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text }) -join " "
            }
        )

        ($Private:Invocation | Sort-Object) | Should -Be @(
            ""
            "-IncludeHeader"
            '-OutputFormat "PowerShellArray"'
            '-OutputFormat "SqlArray"'
        )
    }

    It "no longer raises a Click on a shared menu item" {
        # The mechanism that could only ever work from outside a closure. Asserted on the text as well
        # as the structure, because this is the line that threw.
        $Script:SourceText | Should -Not -Match 'DataGridQueryResultMenuItem\w*\.RaiseEvent'
    }
}

Describe "The focus handler clears the column-selection anchor through a function" {

    It "calls Clear-DataGridColumnSelectionAnchor" {
        (Script:Get-CommandByName -Name "Clear-DataGridColumnSelectionAnchor").Count | Should -Be 1
    }

    It "assigns the anchor variable nowhere in this file" {
        # The silent half of #166. A bare assignment here is lost to the closure's scope, so the only
        # correct way to touch this state from a handler is the function above.
        $Script:SourceText | Should -Not -Match '\$Script:DataGridQueryResultColumnSelectionAnchor\s*='
    }
}
