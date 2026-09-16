#Requires -Version 7.0
# Tests for the log window's session-log-file row (issue #138).
#
# The row now has to be correct twice: when the window opens, and after the "Write log file"
# checkbox has started or stopped the file. Both go through this one function, so this is where
# "the label agrees with the file" is asserted.
#
# No WPF types anywhere: CI runs headless pwsh, which cannot resolve System.Windows.*. Plain objects
# with the same three properties the function touches are enough, and they make "was it set?"
# directly assertable.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Update-LogFormSessionLogPath.ps1")

    function New-FakeLogForm {
        return [PSCustomObject]@{
            Elements = [PSCustomObject]@{
                TextBlockSessionLogPath = [PSCustomObject]@{ Text = "unset"; ToolTip = "unset" }
                ButtonOpenLogFolder     = [PSCustomObject]@{ IsEnabled = $null }
            }
        }
    }
}

Describe "Update-LogFormSessionLogPath" {

    BeforeEach {
        $Script:LogForm = New-FakeLogForm
        $Script:SessionLogFile = $null
    }

    Context "A file is being written" {

        It "shows the path, which is what a user pastes into a support ticket" {
            $Script:SessionLogFile = [PSCustomObject]@{ Path = "C:\Users\someone\AppData\Roaming\OmadaSqlTroubleshooter\logs\OmadaSqlTroubleshooter.log" }

            Update-LogFormSessionLogPath

            $Script:LogForm.Elements.TextBlockSessionLogPath.Text | Should -BeExactly $Script:SessionLogFile.Path
            $Script:LogForm.Elements.TextBlockSessionLogPath.ToolTip | Should -BeExactly $Script:SessionLogFile.Path
        }

        It "enables the Folder button, so the file can be reached without reopening the window" {
            $Script:SessionLogFile = [PSCustomObject]@{ Path = "C:\logs\OmadaSqlTroubleshooter.log" }

            Update-LogFormSessionLogPath

            $Script:LogForm.Elements.ButtonOpenLogFolder.IsEnabled | Should -BeTrue
        }
    }

    Context "No file is being written" {

        It "says so, and points at the checkbox rather than at the settings file" {
            Update-LogFormSessionLogPath

            $Script:LogForm.Elements.TextBlockSessionLogPath.Text | Should -BeExactly "No session log file is being written."
            $Script:LogForm.Elements.TextBlockSessionLogPath.ToolTip | Should -Match "Write log file"
            $Script:LogForm.Elements.TextBlockSessionLogPath.ToolTip | Should -Not -Match "settings file"
        }

        It "disables the Folder button, which has no folder to open" {
            Update-LogFormSessionLogPath

            $Script:LogForm.Elements.ButtonOpenLogFolder.IsEnabled | Should -BeFalse
        }

        It "treats a stopped file as no file, however recently it was written" {
            # Set-SessionLogFileEnabled clears Path when the checkbox is unticked and keeps the rest
            # of the state for resuming. A row that still showed the old path would be claiming a
            # file is being written that has just been closed.
            $Script:SessionLogFile = [PSCustomObject]@{ Path = $null; SessionKey = "20260915-080000" }

            Update-LogFormSessionLogPath

            $Script:LogForm.Elements.TextBlockSessionLogPath.Text | Should -BeExactly "No session log file is being written."
            $Script:LogForm.Elements.ButtonOpenLogFolder.IsEnabled | Should -BeFalse
        }
    }

    Context "A window that does not have the row" {

        # Assigning to a property of $null throws, Open-LogForm's catch logs an ERROR, and an ERROR
        # under $ErrorActionPreference = Stop throws again - so a XAML mismatch must not turn
        # "open the log window" into an error cascade over a label.

        It "does nothing when the path label is missing" {
            $Script:LogForm.Elements.TextBlockSessionLogPath = $null

            { Update-LogFormSessionLogPath } | Should -Not -Throw
        }

        It "does nothing when the Folder button is missing" {
            $Script:LogForm.Elements.ButtonOpenLogFolder = $null

            { Update-LogFormSessionLogPath } | Should -Not -Throw
        }

        It "does nothing when there is no log window at all" {
            # The checkbox handler cannot reach this, but a future caller on another path could.
            $Script:LogForm = $null

            { Update-LogFormSessionLogPath } | Should -Not -Throw
        }
    }
}
