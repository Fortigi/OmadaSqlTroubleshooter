#Requires -Version 7.0
# Issue #128: the Messages pane reused the dialog text verbatim, so every pane message carried a
# "Warning:"/"Failure occurred:" heading and two leading blank lines that were only ever meant to
# separate a modal's summary from its detail. The status bar (issue #117) already names the outcome,
# so the pane now gets its own plain copy of the message - $LogMessagePaneText - built alongside
# $LogMessageDialog.Text but never given a heading.
#
# Write-LogOutput itself needs the whole application (a form, a log window, a tab table) to reach the
# TabScoped branch that calls Add-TabMessage, so - like Write-LogOutputDialogFormat.Tests.ps1 - the
# statements under test are lifted out and run directly, with a source guard proving the copy still
# matches the original.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:LogOutputSource = Get-Content -Path (Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Write-LogOutput.ps1") -Raw

    function script:Format-LogTexts {
        param(
            [string]$Message,
            [ValidateSet("WARNING", "ERROR")]
            [string]$LogType,
            [string]$TabContext = "Mve: query",
            $StatusCode,
            [string]$ReasonPhrase
        )

        $Dialog = @{ Text = $Message; Title = $null }
        $Pane = @{ Text = $Message }

        if ($LogType -eq "WARNING") {
            $Dialog.Text = "Warning:`r`n`r`n{0}" -f $Dialog.Text
            $Dialog.Title = "Warning - {0}" -f $TabContext
        }
        else {
            $Dialog.Title = "Error - {0}" -f $TabContext
            if ($null -ne $StatusCode) {
                $Dialog.Title = "{0} - ({1} - {2})" -f $Dialog.Title, $StatusCode, $ReasonPhrase
                $Dialog.Text = "Failure {0} - {1} occurred:`r`n`r`n{2}" -f $StatusCode, $ReasonPhrase, $Dialog.Text
                $Pane.Text = "{0} ({1} - {2})" -f $Pane.Text, $StatusCode, $ReasonPhrase
            }
            else {
                $Dialog.Text = "Failure occurred:`r`n`r`n{0}" -f $Dialog.Text
            }
        }

        return [pscustomobject]@{ Dialog = $Dialog; Pane = $Pane }
    }
}

Describe "The Messages pane text carries no dialog heading" {

    It "gives a WARNING pane no heading or leading blank lines" {
        $Result = Format-LogTexts -Message "Query did not return any results" -LogType WARNING

        $Result.Pane.Text | Should -Be "Query did not return any results"
        $Result.Pane.Text | Should -Not -Match "^Warning:"
        $Result.Pane.Text | Should -Not -Match "^\r?\n\r?\n"
    }

    It "still gives the WARNING dialog its heading, unchanged" {
        $Result = Format-LogTexts -Message "Query did not return any results" -LogType WARNING

        $Result.Dialog.Text | Should -Be "Warning:`r`n`r`nQuery did not return any results"
    }

    It "gives an ERROR pane no heading or leading blank lines" {
        $Result = Format-LogTexts -Message "Invalid column name 'Idenity'." -LogType ERROR

        $Result.Pane.Text | Should -Be "Invalid column name 'Idenity'."
        $Result.Pane.Text | Should -Not -Match "^Failure"
        $Result.Pane.Text | Should -Not -Match "^\r?\n\r?\n"
    }

    It "still gives the ERROR dialog its heading, unchanged" {
        $Result = Format-LogTexts -Message "Invalid column name 'Idenity'." -LogType ERROR

        $Result.Dialog.Text | Should -Be "Failure occurred:`r`n`r`nInvalid column name 'Idenity'."
    }

    It "keeps the HTTP status code visible in the pane as plain trailing detail" {
        # Without this the status code would vanish entirely from what a tab user sees: the dialog
        # Title carries it today, but a tab-scoped failure never raises a dialog (issue #93).
        $Result = Format-LogTexts -Message "The query pipeline failed" -LogType ERROR -StatusCode 500 -ReasonPhrase "Internal Server Error"

        $Result.Pane.Text | Should -Be "The query pipeline failed (500 - Internal Server Error)"
        $Result.Pane.Text | Should -Not -Match "^Failure"
        $Result.Pane.Text | Should -Not -Match "occurred:"
        $Result.Pane.Text | Should -Not -Match "^\r?\n\r?\n"
    }

    It "still gives the ERROR-with-status-code dialog its heading and status code, unchanged" {
        $Result = Format-LogTexts -Message "The query pipeline failed" -LogType ERROR -StatusCode 500 -ReasonPhrase "Internal Server Error"

        $Result.Dialog.Text | Should -Be "Failure 500 - Internal Server Error occurred:`r`n`r`nThe query pipeline failed"
        $Result.Dialog.Title | Should -Be "Error - Mve: query - (500 - Internal Server Error)"
    }
}

Describe "Write-LogOutput's own source keeps those shapes" {
    # The block above is a copy, so it can only prove the shapes are right - not that Write-LogOutput
    # still produces them. These guard against the copy and the original drifting.

    It "starts the pane text as the plain message, not the dialog text" {
        $script:LogOutputSource | Should -Match '\$LogMessagePaneText\s*=\s*\$Message'
    }

    It "routes a tab-scoped message to the pane's own text, not the dialog's" {
        $script:LogOutputSource | Should -Match 'Add-TabMessage -TabSession \(Get-ActiveTabSession\) -Text \$LogMessagePaneText'
    }

    It "still routes application-level dialogs through the dialog text" {
        $script:LogOutputSource | Should -Match 'Show-LogMessageDialog -Text \$LogMessageDialog\.Text'
        $script:LogOutputSource | Should -Match '\[System\.Windows\.MessageBox\]::Show\(\(Limit-MessageBoxText -Text \$LogMessageDialog\.Text\)'
    }

    It "appends the status code to the pane text as plain detail, not through the heading format" {
        $script:LogOutputSource | Should -Match '\$LogMessagePaneText\s*=\s*"\{0\} \(\{1\} - \{2\}\)"\s*-f\s*\$LogMessagePaneText,\s*\$ErrorObject\.Exception\.StatusCode'
    }

    It "leaves the session log file line reading from LogMessage.Text, unaffected by the pane split (issue #121)" {
        # The session log file writes the masked $LogMessage.Text line - built from the timestamp,
        # log type and tab context, never from $LogMessageDialog.Text or $LogMessagePaneText - and
        # this issue must not change that.
        $script:LogOutputSource | Should -Match 'Write-SessionLogFile -Line \(\(\$LogMessage\.Text\) -join "`r`n"\) -LogType \$LogType'
    }
}

Describe "Messages accumulating within one execute still read as a list" {
    BeforeAll {
        $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
        . (Join-Path $PrivatePath -ChildPath "Write-TabMessage.ps1")
    }

    BeforeEach {
        $Script:TabA = [pscustomobject]@{
            Id            = "tab-A"
            QueryMessages = [System.Collections.Generic.List[string]]::new()
            Elements      = @{
                TextBoxQueryMessages  = [pscustomobject]@{ Text = "" }
                TabControlQueryOutput = [pscustomobject]@{ SelectedIndex = 0 }
            }
        }
    }

    It "starts the first message at the top of the pane, with nothing above it" {
        Add-TabMessage -TabSession $Script:TabA -Text "Rows read: 0"

        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Be "Rows read: 0"
    }

    It "does not start the pane text with a newline, even once a second message has arrived" {
        Add-TabMessage -TabSession $Script:TabA -Text "Rows read: 0"
        Add-TabMessage -TabSession $Script:TabA -Text "Completion time: 00:00:01"

        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Not -Match "^\r?\n"
    }

    It "keeps several messages visibly separated rather than run together" {
        Add-TabMessage -TabSession $Script:TabA -Text "Invalid column name 'Idenity'."
        Add-TabMessage -TabSession $Script:TabA -Text "Rows read: 0"
        Add-TabMessage -TabSession $Script:TabA -Text "Completion time: 00:00:01"

        # One blank line BETWEEN entries - splitting on a double line break, not a single one,
        # since a single "`r`n" join would run a multi-line message's own internal lines together
        # with the next entry (see the multi-line test below).
        $Entries = $Script:TabA.Elements.TextBoxQueryMessages.Text -split "`r`n`r`n"
        $Entries.Count | Should -Be 3
        $Entries[0] | Should -Be "Invalid column name 'Idenity'."
        $Entries[1] | Should -Be "Rows read: 0"
        $Entries[2] | Should -Be "Completion time: 00:00:01"
    }

    It "separates two multi-line messages with exactly one blank line, not run together" {
        # The case the fix is actually for: a multi-line SQL error followed by a warning. Before
        # issue #128, the dialog headings this pane no longer carries were what separated entries;
        # a plain single "`r`n" join would leave nothing distinguishing the boundary between these
        # two messages from the line break inside the first one.
        $SqlError = "Msg 207, Level 16, State 1, Line 4`r`nInvalid column name 'Idenity'."
        $Warning = "Query did not return any results"

        Add-TabMessage -TabSession $Script:TabA -Text $SqlError
        Add-TabMessage -TabSession $Script:TabA -Text $Warning

        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Be ($SqlError, $Warning -join "`r`n`r`n")

        $Entries = $Script:TabA.Elements.TextBoxQueryMessages.Text -split "`r`n`r`n"
        $Entries.Count | Should -Be 2
        $Entries[0] | Should -Be $SqlError
        $Entries[1] | Should -Be $Warning
    }
}
