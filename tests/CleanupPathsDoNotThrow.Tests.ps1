#Requires -Version 7.0
# Write-LogOutput ends an ERROR with Write-Error, which under this application's
# $ErrorActionPreference = Stop is TERMINATING. That is correct where a caller should stop, and a trap
# everywhere else - it is the same defect that turned one HTTP 500 into five stacked dialogs.
#
# These four functions all sit on paths that must complete: tab teardown, tab-close cleanup, the
# Execute/Cancel button repaint that runs on every tab switch, and window re-activation - which is
# called from inside the dialog-display path itself, so an ERROR there would throw out of the code
# that was reporting an error.
#
# Asserted against the source rather than by executing each function, because reproducing four
# different failure modes would mean four elaborate harnesses to prove one property they share.
# A future edit that reintroduces a terminating log on any of them fails here.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
}

Describe "Cleanup and teardown paths never log a terminating ERROR" {
    $script:Cases = @(
        @{ Name = "Set-ExecuteQueryButtonState"; Why = "runs on every tab switch and during execute teardown" }
        @{ Name = "Remove-PendingBackgroundRequest"; Why = "is the tab-close cleanup guard" }
        @{ Name = "Complete-TabClose"; Why = "is the outer guard of the whole tab-close operation" }
        @{ Name = "Restore-MainFormFocus"; Why = "is called from inside the dialog-display path" }
    )

    It "<Name> does not raise a terminating ERROR, because it <Why>" -TestCases $script:Cases {
        param($Name, $Why)

        $Private:Source = Get-Content -Path (Join-Path $script:PrivatePath -ChildPath ("{0}.ps1" -f $Name)) -Raw

        # -LogType ERROR is the terminating form. Write-ContainedErrorLog is not: it reports at ERROR
        # and swallows the throw, which is exactly what these paths need when the user should still
        # be told.
        $Private:Source | Should -Not -Match '\-LogType\s+ERROR'
    }

    It "<Name> still reports the failure rather than swallowing it silently" -TestCases $script:Cases {
        param($Name, $Why)

        $Private:Source = Get-Content -Path (Join-Path $script:PrivatePath -ChildPath ("{0}.ps1" -f $Name)) -Raw

        # A catch that reports nothing hides a real defect. Each of these logs at some level, or
        # routes through the contained reporter.
        $Private:Source | Should -Match '(Write-ContainedErrorLog|-LogType\s+(WARNING|DEBUG))'
    }
}
