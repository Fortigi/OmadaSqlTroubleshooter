#Requires -Version 7.0
# Regression tests for a defect found while building issue #40's E2E coverage.
#
# Nothing ever removed a closing tab's entries from $Script:PendingWebViewCompletions. That was
# survivable while the queue only held WebView2 editor tasks, but a background request's completion
# calls Set-ActiveTabContext with its own TabSession - repointing $Script:MainForm.Elements,
# $Script:RunTimeData, $Script:AppConfig and $Script:ConnectionStatus onto a tab that no longer
# exists - and then writes results into disposed WPF elements. The restore in the poll timer's
# finally cannot undo it either: Get-ActiveTabSession returns $null when the closing tab was the
# active one, so the restore is skipped and the whole application is left pointing at a dead tab.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Remove-PendingBackgroundRequest.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function script:New-QueueItem {
        param(
            [string]$TabId,
            [switch]$IsEditorTask,
            [switch]$WithShell
        )
        $Shell = $null
        if ($WithShell) {
            $Shell = [powershell]::Create()
            [void]$Shell.AddScript({ Start-Sleep -Seconds 30 })
            [void]$Shell.BeginInvoke()
        }
        return [pscustomobject]@{
            StartedUtc  = $(if ($IsEditorTask) { $null } else { [DateTime]::UtcNow })
            TabSession  = [pscustomobject]@{ Id = $TabId; DisplayName = $TabId }
            Shell       = $Shell
            IsCancelled = $false
        }
    }
}

Describe "Remove-PendingBackgroundRequest" {
    BeforeEach {
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
    }

    It "removes the closing tab's background requests from the queue" {
        $Doomed = New-QueueItem -TabId "tab-A"
        $Script:PendingWebViewCompletions.Add($Doomed)

        Remove-PendingBackgroundRequest -TabSession ([pscustomobject]@{ Id = "tab-A"; DisplayName = "A" })

        $Script:PendingWebViewCompletions.Count | Should -Be 0
    }

    It "leaves other tabs' requests alone" {
        $Script:PendingWebViewCompletions.Add((New-QueueItem -TabId "tab-A"))
        $Survivor = New-QueueItem -TabId "tab-B"
        $Script:PendingWebViewCompletions.Add($Survivor)

        Remove-PendingBackgroundRequest -TabSession ([pscustomobject]@{ Id = "tab-A"; DisplayName = "A" })

        $Script:PendingWebViewCompletions.Count | Should -Be 1
        $Script:PendingWebViewCompletions[0].TabSession.Id | Should -Be "tab-B"
    }

    It "leaves WebView2 editor tasks alone even for the closing tab" {
        # They are not ours to stop, they carry no worker, and the existing behaviour around them is
        # deliberately unchanged.
        $Script:PendingWebViewCompletions.Add((New-QueueItem -TabId "tab-A" -IsEditorTask))

        Remove-PendingBackgroundRequest -TabSession ([pscustomobject]@{ Id = "tab-A"; DisplayName = "A" })

        $Script:PendingWebViewCompletions.Count | Should -Be 1
    }

    It "marks what it removes as cancelled" {
        # So anything still holding a reference - a Cancel handler racing the tab close - can tell
        # the request was abandoned rather than left running.
        $Doomed = New-QueueItem -TabId "tab-A"
        $Script:PendingWebViewCompletions.Add($Doomed)

        Remove-PendingBackgroundRequest -TabSession ([pscustomobject]@{ Id = "tab-A"; DisplayName = "A" })

        $Doomed.IsCancelled | Should -BeTrue
    }

    It "stops and disposes the worker so its runspace is not returned to the pool" {
        # A pipeline killed mid-request leaves a half-read HTTP stream and a WebRequestSession in an
        # unknown state. Disposing the shell is what releases the runspace, and a disposed
        # [powershell] refuses further use - which is what this asserts.
        $Doomed = New-QueueItem -TabId "tab-A" -WithShell
        $Script:PendingWebViewCompletions.Add($Doomed)

        Remove-PendingBackgroundRequest -TabSession ([pscustomobject]@{ Id = "tab-A"; DisplayName = "A" })

        { $Doomed.Shell.AddScript({ 1 }) } | Should -Throw
    }

    It "does not throw when the queue does not exist yet" {
        $Script:PendingWebViewCompletions = $null

        { Remove-PendingBackgroundRequest -TabSession ([pscustomobject]@{ Id = "tab-A"; DisplayName = "A" }) } | Should -Not -Throw
    }

    It "does not throw for a tab with nothing in flight" {
        { Remove-PendingBackgroundRequest -TabSession ([pscustomobject]@{ Id = "tab-Z"; DisplayName = "Z" }) } | Should -Not -Throw
    }
}
