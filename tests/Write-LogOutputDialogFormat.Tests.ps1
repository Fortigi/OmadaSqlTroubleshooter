#Requires -Version 7.0
# Two user-visible formatting defects in the ERROR dialog, both from a format string being handed the
# wrong thing. Neither was caught by any existing test because nothing asserted what the dialog
# actually says - only that one was raised.
#
# The title was built with "+=" against a format whose {0} was the title itself:
#   "Error - Mve: queryError - Mve: query - (500 - Internal Server Error)"
#
# The body was passed message-first, so the user's real error landed in the status-code slot and the
# reason phrase replaced the message:
#   "Failure The query pipeline failed - 500 occurred:
#
#    Internal Server Error"

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:LogOutputSource = Get-Content -Path (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Write-LogOutput.ps1") -Raw

    # The two statements under test, lifted out and run directly. Write-LogOutput itself needs the
    # whole application - a form, a log window, a tab table - to reach this branch, and none of that
    # is what these assertions are about.
    function script:Format-ErrorDialog {
        param([string]$TabContext, [string]$Message, [int]$StatusCode, [string]$ReasonPhrase)

        $Dialog = @{ Title = "Error - {0}" -f $TabContext; Text = $Message }
        $Dialog.Title = "{0} - ({1} - {2})" -f $Dialog.Title, $StatusCode, $ReasonPhrase
        $Dialog.Text = "Failure {0} - {1} occurred:`r`n`r`n{2}" -f $StatusCode, $ReasonPhrase, $Dialog.Text
        return $Dialog
    }
}

Describe "The ERROR dialog says what it means" {
    BeforeEach {
        $script:Dialog = Format-ErrorDialog -TabContext "Mve: query" -Message "The query pipeline failed" -StatusCode 500 -ReasonPhrase "Internal Server Error"
    }

    It "names the tab once, not twice" {
        $script:Dialog.Title | Should -Be "Error - Mve: query - (500 - Internal Server Error)"
    }

    It "does not repeat the word Error" {
        # The duplication was visible as "...queryError - ..." run together, which is how it was
        # spotted at all.
        ([regex]::Matches($script:Dialog.Title, "Error - ")).Count | Should -Be 1
    }

    It "puts the status code where the status code goes" {
        $script:Dialog.Text | Should -Match "^Failure 500 - Internal Server Error occurred:"
    }

    It "keeps the user's actual message in the body" {
        $script:Dialog.Text | Should -Match "The query pipeline failed"
    }

    It "does not put the message into the status-code slot" {
        $script:Dialog.Text | Should -Not -Match "Failure The query pipeline failed"
    }
}

Describe "Write-LogOutput's own source keeps those shapes" {
    # The block above is a copy, so it can only prove the format strings are right - not that
    # Write-LogOutput still uses them. These two guard against the copy and the original drifting.

    It "assigns the title rather than appending it to itself" {
        $script:LogOutputSource | Should -Not -Match '\$LogMessageDialog\.Title\s*\+='
    }

    It "passes the status code and reason before the message text" {
        $script:LogOutputSource | Should -Match '"Failure \{0\} - \{1\} occurred:[^"]*"\s*-f\s*\$ErrorObject\.Exception\.StatusCode'
    }
}
