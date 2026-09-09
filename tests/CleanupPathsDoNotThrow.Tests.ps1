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

Describe "The window's Closing handler never logs a terminating ERROR" {
    # The same property, one directory over, and the one the four cases above missed. It is worth its
    # own block because what it costs is different: the handler's last act is Close-OmadaRequestPool,
    # and worker threads left open keep the PROCESS alive after the window has gone. A terminating
    # log unwinding out of the handler is therefore not a lost message - it is an application that
    # does not exit.
    BeforeAll {
        $script:ClosingSource = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Events\MainForm.Definition.ps1") -Raw

        # Just the Closing handler. The file holds other handlers where a terminating ERROR is the
        # right answer, so matching the whole file would assert something untrue.
        $script:ClosingHandler = ([regex]::Match($script:ClosingSource, '(?s)Add_Closing\(\{.*?\n    \}\)')).Value
    }

    It "finds the Closing handler to check" {
        # Without this the two assertions below pass vacuously on an empty string.
        $script:ClosingHandler | Should -Not -BeNullOrEmpty
        $script:ClosingHandler | Should -Match 'Close-OmadaRequestPool'
    }

    It "does not raise a terminating ERROR while the window is closing" {
        $script:ClosingHandler | Should -Not -Match '\-LogType\s+ERROR'
    }

    It "still reports a failed shutdown rather than swallowing it" {
        $script:ClosingHandler | Should -Match 'Write-ContainedErrorLog'
    }
}
