#Requires -Version 7.0
# "Is this tab executing?" - the single question the Execute/Cancel button is derived from (#40).
#
# It reads the completion queue rather than a per-tab flag on purpose: a flag has to be cleared on
# every path a request can leave by (success, failure, cancellation, and abandonment when its tab is
# closed) and one missed path leaves a tab that can never execute again. These tests pin the queue
# reading down, including the cases where it must answer "no".

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Get-ActiveExecuteQueryRequest.ps1")

    $Script:ExecuteQueryRequestDescription = "Execute query"

    function Get-ActiveTabSession { return $script:StubActiveTab }

    function script:New-QueueItem {
        param(
            [string]$TabId = "tab-A",
            [string]$Description = "Execute query",
            [switch]$Cancelled
        )
        return [pscustomobject]@{
            Description = $Description
            TabSession  = [pscustomobject]@{ Id = $TabId }
            IsCancelled = [bool]$Cancelled
        }
    }
}

Describe "Get-ActiveExecuteQueryRequest" {
    BeforeEach {
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $script:StubActiveTab = [pscustomobject]@{ Id = "tab-A" }
    }

    It "finds the active tab's execute request" {
        $Script:PendingWebViewCompletions.Add((New-QueueItem))

        (Get-ActiveExecuteQueryRequest) | Should -Not -BeNullOrEmpty
    }

    It "answers null when nothing is running" {
        Get-ActiveExecuteQueryRequest | Should -BeNullOrEmpty
    }

    It "ignores another tab's execute request" {
        # Otherwise one tab's query would put every other tab's button into Cancel.
        $Script:PendingWebViewCompletions.Add((New-QueueItem -TabId "tab-B"))

        Get-ActiveExecuteQueryRequest | Should -BeNullOrEmpty
    }

    It "ignores requests that are not executes" {
        # A schema fetch is in flight constantly; it must not turn Execute into Cancel.
        $Script:PendingWebViewCompletions.Add((New-QueueItem -Description "SQL schema"))

        Get-ActiveExecuteQueryRequest | Should -BeNullOrEmpty
    }

    It "ignores an already-cancelled request" {
        # The pipeline may take a moment to stop, but the request is over the instant the user asked
        # for it to be - otherwise Cancel could not flip the button back in the same click.
        $Script:PendingWebViewCompletions.Add((New-QueueItem -Cancelled))

        Get-ActiveExecuteQueryRequest | Should -BeNullOrEmpty
    }

    It "can be asked about a specific tab rather than the active one" {
        # What the tab-switch path needs: the button must show Cancel for a tab that is executing
        # even when it is not the one on screen at the moment the question is asked.
        $Script:PendingWebViewCompletions.Add((New-QueueItem -TabId "tab-B"))

        Get-ActiveExecuteQueryRequest -TabSession ([pscustomobject]@{ Id = "tab-B" }) | Should -Not -BeNullOrEmpty
    }

    It "answers null when there is no active tab at all" {
        $script:StubActiveTab = $null
        $Script:PendingWebViewCompletions.Add((New-QueueItem))

        Get-ActiveExecuteQueryRequest | Should -BeNullOrEmpty
    }

    It "answers null when the queue does not exist yet" {
        $Script:PendingWebViewCompletions = $null

        Get-ActiveExecuteQueryRequest | Should -BeNullOrEmpty
    }
}
