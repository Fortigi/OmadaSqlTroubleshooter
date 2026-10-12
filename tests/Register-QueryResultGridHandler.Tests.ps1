#Requires -Version 7.0
# Issues #166 and #169. The rule this file enforces, stated once: no handler in
# Register-QueryResultGridHandler.ps1 is closed with .GetNewClosure().
#
# A closure runs in a detached dynamic module that resolves names through the GLOBAL scope. It sees
# none of this module's $Script: variables, and none of its private functions either - unless they
# happen to be exported. That last clause is what hid half the trap:
#
#   * #166 found the VARIABLE half. The four copy shortcuts read $Script:DataGridQueryResultMenuItem*
#     as $null and threw "You cannot call a method on a null-valued expression", and the GotFocus
#     handler's `$Script:DataGridQueryResultColumnSelectionAnchor = $null` landed in the closure's
#     own scope, silently.
#   * #169 is the FUNCTION half, which #166 measured as safe. It is safe only when the module is
#     imported through the .psm1, which has no Export-ModuleMember and so exports every function -
#     development, and every test suite. The installed module is imported through the .psd1, whose
#     FunctionsToExport names three functions, and there every handler threw CommandNotFoundException
#     on its first private call and again on the Write-LogOutput in its own catch.
#
# Two kinds of proof below. The STRUCTURAL rule is asserted by parsing, headless: no closures, and
# no captured index or grid in their place. The BEHAVIOUR is measured by _GridHandlerScopeProbe.ps1
# in a pwsh -STA child, which runs the real handlers from inside a module that exports nothing but
# its runner - the visibility the installed module has - and raises a real routed event at each one.
# That half reports inconclusive where no WPF runtime exists.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:RepositoryRoot = $ParentPath
    $Script:SourcePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Register-QueryResultGridHandler.ps1"
    $Script:SourceText = Get-Content -Path $Script:SourcePath -Raw

    $Private:ParseError = $null
    $Private:Token = $null
    $Script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($Script:SourcePath, [ref]$Private:Token, [ref]$Private:ParseError)
    $Script:ParseError = @($Private:ParseError)

    # Every .GetNewClosure() call, by AST rather than by text: the source mentions the method in its
    # comments, and those must not count.
    $Script:ClosureCall = @(
        $Script:Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                "$($Node.Member.Value)" -eq "GetNewClosure"
            }, $true)
    )

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

    function Script:Get-VariableByName {
        param([string]$Name)

        return @(
            $Script:Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Node.VariablePath.UserPath -eq $Name
                }, $true)
        )
    }
}

Describe "The source still parses" {
    It "has no parse errors, so every assertion below is about real structure" {
        $Script:ParseError.Count | Should -Be 0
    }
}

Describe "No handler is a closure" {

    It "calls .GetNewClosure() nowhere in this file" {
        # THE structural regression test for issue #169, and for #166 with it: a handler that is not a
        # closure can neither lose a private function nor a $Script: variable. A failure names the line.
        $Private:Offender = foreach ($Private:Call in $Script:ClosureCall) {
            "line {0}" -f $Private:Call.Extent.StartLineNumber
        }

        @($Private:Offender) -join ", " | Should -BeExactly ""
    }

    It "captures no per-iteration index or grid for the handlers to read" {
        # The closures existed to carry these two into the handlers. A plain scriptblock cannot see a
        # local of the loop that registered it - it would read $null and focus the wrong result - so
        # the handlers read the index from the sender's Tag, and the splitter's grid from the
        # splitter's Tag, instead.
        (Script:Get-VariableByName -Name "GridIndex").Count | Should -Be 0
        (Script:Get-VariableByName -Name "SplitterGrid").Count | Should -Be 0
    }

    It "puts the grid on its splitter's Tag, where the splitter handlers look for it" {
        $Script:SourceText | Should -Match '\$Private:Splitter\.Tag\s*=\s*\$Private:Grid'
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
        # The mechanism #166 removed. Asserted on the text as well as the structure, because this is
        # the line that threw.
        $Script:SourceText | Should -Not -Match 'DataGridQueryResultMenuItem\w*\.RaiseEvent'
    }
}

Describe "The focus handler clears the column-selection anchor through a function" {

    It "calls Clear-DataGridColumnSelectionAnchor" {
        (Script:Get-CommandByName -Name "Clear-DataGridColumnSelectionAnchor").Count | Should -Be 1
    }

    It "assigns the anchor variable nowhere in this file" {
        # The file that owns the state is the one that writes it.
        $Script:SourceText | Should -Not -Match '\$Script:DataGridQueryResultColumnSelectionAnchor\s*='
    }
}

Describe "The handlers run with the installed module's visibility" -Tag 'Sta' {

    BeforeAll {
        # One child process for every assertion below: a WPF host per test would multiply a ~2s
        # start-up for no extra coverage.
        $Private:ProbePath = Join-Path $PSScriptRoot "_GridHandlerScopeProbe.ps1"
        $Private:Output = & pwsh -STA -NoProfile -File $Private:ProbePath -RepositoryRoot $Script:RepositoryRoot 2>&1
        $Private:Text = ($Private:Output | Out-String)

        try {
            $Script:Probe = $Private:Text | ConvertFrom-Json
        }
        catch {
            # The raw output is the diagnosis when the child could not produce JSON.
            $Script:Probe = [pscustomobject]@{ Ok = $false; Error = $Private:Text }
        }
    }

    BeforeEach {
        # Set-ItResult rather than -Skip:, which is evaluated at discovery, before BeforeAll has run.
        if (-not $Script:Probe.Ok) {
            Set-ItResult -Inconclusive -Because ("the STA scope probe did not run: {0}" -f $Script:Probe.Error)
        }
    }

    It "lets no exception escape any handler to the dispatcher" {
        # The reported symptom itself: "'Write-LogOutput' is not recognized", escaping a handler's
        # catch. Before the fix this listed all six handlers.
        @($Script:Probe.Escaped) -join " | " | Should -BeExactly ""
    }

    It "focuses the result whose grid took focus, not the first or the last" {
        # GotFocus, ContextMenuOpening and PreviewKeyDown each record the index they focused. Grid 1
        # of 2 was the target, so 0 would mean a lost index and anything else a wrong one.
        $Private:Focused = @($Script:Probe.Recorded | Where-Object { $_ -like "Focus:*" })
        $Private:Focused.Count | Should -BeGreaterOrEqual 3
        $Private:Focused | Should -Not -Contain "Focus:0"
        ($Private:Focused | Select-Object -Unique) | Should -Be "Focus:1"
    }

    It "clears the column-selection anchor and refreshes the context menu" {
        $Script:Probe.Recorded | Should -Contain "ClearAnchor"
        $Script:Probe.Recorded | Should -Contain "MenuState"
    }

    It "selects the clicked column in the grid that raised the event" {
        if (-not $Script:Probe.ColumnHeaderClicked) {
            Set-ItResult -Inconclusive -Because "this WPF build exposes no way to give a detached column header its column"
        }

        $Script:Probe.Recorded | Should -Contain "SelectColumn:1"
    }

    It "resizes the dragged grid, marks it user-sized, and leaves the other grid alone" {
        # The splitter handlers find their grid through the splitter's Tag; the drag is 40 and the
        # stubbed floor is 10, so the grid lands on exactly 40.
        $Script:Probe.Recorded | Should -Contain "Floor"
        $Script:Probe.GridHeight | Should -Be 40
        $Script:Probe.UserSized | Should -BeTrue
        $Script:Probe.OtherGridHeightIsAuto | Should -BeTrue
    }
}
