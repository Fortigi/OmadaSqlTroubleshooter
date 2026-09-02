#Requires -Version 7.0
# The elapsed-time indicator (issue #40). Before this, $Script:RunTimeData.StopWatch was read exactly
# once - at the very end of an execute - so the number only appeared after the wait was over.
#
# The two properties worth protecting are both about NOT writing where it should not: it must write
# to the OWNING tab's status bar rather than whatever tab is on screen (it is driven from a timer,
# with no Set-ActiveTabContext), and it must leave WebView2 editor tasks and cancelled requests
# alone.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Update-BackgroundRequestElapsedTime.ps1")

    function script:New-TimePending {
        param(
            $StartedUtc = ([DateTime]::UtcNow.AddSeconds(-5)),
            [switch]$Cancelled,
            [switch]$NoTimeBlock
        )
        $Elements = @{}
        if (-not $NoTimeBlock) {
            $Elements.TextBlockStatusBarQueryTime = [pscustomobject]@{ Text = "-" }
        }
        return [pscustomobject]@{
            StartedUtc  = $StartedUtc
            IsCancelled = [bool]$Cancelled
            TabSession  = [pscustomobject]@{ Id = "tab-1"; Elements = $Elements }
        }
    }
}

Describe "Update-BackgroundRequestElapsedTime" {
    It "writes an elapsed time into the owning tab's status bar" {
        $Pending = New-TimePending

        Update-BackgroundRequestElapsedTime -Pending @($Pending)

        $Pending.TabSession.Elements.TextBlockStatusBarQueryTime.Text | Should -Not -Be "-"
        # Same shape as the final value Reset-ExecuteQueryUiState writes from the stopwatch, so the
        # indicator does not visibly change format when the request completes.
        $Pending.TabSession.Elements.TextBlockStatusBarQueryTime.Text | Should -Match '^\d{2}:\d{2}:\d{2}'
    }

    It "writes to each pending request's own tab, not to one shared element" {
        # This runs from a timer with no Set-ActiveTabContext, so two tabs executing at once must
        # each count up in their own status bar.
        $First = New-TimePending
        $Second = New-TimePending
        $Second.TabSession.Id = "tab-2"

        Update-BackgroundRequestElapsedTime -Pending @($First, $Second)

        $First.TabSession.Elements.TextBlockStatusBarQueryTime.Text | Should -Not -Be "-"
        $Second.TabSession.Elements.TextBlockStatusBarQueryTime.Text | Should -Not -Be "-"
        [object]::ReferenceEquals(
            $First.TabSession.Elements.TextBlockStatusBarQueryTime,
            $Second.TabSession.Elements.TextBlockStatusBarQueryTime) | Should -BeFalse
    }

    It "ignores WebView2 editor tasks, which have no StartedUtc" {
        $EditorTask = New-TimePending -StartedUtc $null

        Update-BackgroundRequestElapsedTime -Pending @($EditorTask)

        $EditorTask.TabSession.Elements.TextBlockStatusBarQueryTime.Text | Should -Be "-"
    }

    It "ignores a cancelled request" {
        # Its final state is written by the cancel path; continuing to count up over the top of that
        # would be wrong and would look like the query was still running.
        $Cancelled = New-TimePending -Cancelled

        Update-BackgroundRequestElapsedTime -Pending @($Cancelled)

        $Cancelled.TabSession.Elements.TextBlockStatusBarQueryTime.Text | Should -Be "-"
    }

    It "does not throw for a tab with no status bar element" {
        # A tab torn down mid-request has no elements left to write into.
        { Update-BackgroundRequestElapsedTime -Pending @(New-TimePending -NoTimeBlock) } | Should -Not -Throw
    }

    It "does not throw on a null or empty queue" {
        { Update-BackgroundRequestElapsedTime -Pending $null } | Should -Not -Throw
        { Update-BackgroundRequestElapsedTime -Pending @() } | Should -Not -Throw
    }
}
