#Requires -Version 7.0
# Review finding on #83.
#
# The Execute button's handler disables Save, Execute and the output buttons BEFORE it checks its
# preconditions - it has to, because the disable must happen before the dispatcher is pumped to paint
# the popup. When the preconditions then failed it closed the popup and stopped, leaving those
# buttons disabled: a click that changed nothing took the tab's Execute button with it, and only a
# tab switch (which repaints through Set-ExecuteQueryButtonState) brought it back.
#
# Asserted against the source. The handler is a WPF Click handler that pumps the dispatcher and shows
# a popup, none of which runs headlessly on CI; what is checked is the thing that was wrong.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:Handler = Get-Content -Path (Join-Path $ParentPath "src\Lib\Events\MainFormTabContent.Elements.ButtonExecuteQuery.ps1") -Raw
    $script:Reset = Get-Content -Path (Join-Path $ParentPath "src\Lib\Functions\Private\Invoke-ExecuteQuery.ps1") -Raw
}

Describe "Refusing to execute leaves the tab usable" {
    It "disables the buttons before checking the preconditions, which is why this matters" {
        # If this ever stops being true the bug below is no longer reachable and the rest of this
        # file asserts a property nothing depends on - so it is asserted rather than assumed.
        $Private:DisableAt = $script:Handler.IndexOf('ButtonExecuteQuery.IsEnabled = $false')
        $Private:CheckAt = $script:Handler.IndexOf('Test-ConnectionRequirements')

        $Private:DisableAt | Should -BeGreaterThan 0
        $Private:CheckAt | Should -BeGreaterThan $Private:DisableAt
    }

    It "runs the full teardown, not just the popup close" {
        $script:Handler | Should -Match 'Reset-ExecuteQueryUiState -SkipStatusBarTime'
    }

    It "does not write an elapsed time for a run that never issued a request" {
        # -SkipStatusBarTime exists for exactly this case, and Reset-ExecuteQueryUiState's help says
        # so. Passing it is the difference between an honest status bar and one reporting how long
        # the application took to refuse.
        $script:Reset | Should -Match '\.PARAMETER SkipStatusBarTime'
        $script:Handler | Should -Match 'Reset-ExecuteQueryUiState -SkipStatusBarTime'
    }

    It "re-enables Execute and Save through the one function that owns that decision" {
        # Not by setting IsEnabled here: Reset-ExecuteQueryUiState only re-enables for a CONNECTED
        # tab, because a disconnected one must keep them disabled (issue #65). Re-enabling inline
        # would hand a disconnected tab a live Execute button - which is half of what this branch is
        # reached for in the first place.
        $script:Reset | Should -Match 'if \(\$Script:ConnectionStatus\) \{'
        $script:Handler | Should -Not -Match 'ButtonExecuteQuery\.IsEnabled = \$true'
    }
}
