#Requires -Version 7.0
# Unit tests for the E2E harness's drain-timeout handling (tests\e2e\PendingRequestDrain.ps1).
#
# Scheduled E2E run 155 failed three consecutive cases on "pending background requests to drain"
# with no hint of which request hung, and the stuck item stayed on the queue so every later drain
# failed on it too. These tests pin the two things the fix promises: the failure names what was in
# flight, and the queue is empty afterwards - without touching editor tasks, which the drain never
# waited on.

BeforeAll {
    . (Join-Path $PSScriptRoot "e2e" "PendingRequestDrain.ps1")

    function script:New-QueueItem {
        param(
            [string]$Description = "Executing query",
            [string]$TabId = "tab-A",
            [Nullable[DateTime]]$StartedUtc = [DateTime]::UtcNow,
            $Shell = $null,
            [switch]$Finished
        )
        $Task = [pscustomobject]@{ IsCompleted = [bool]$Finished }
        $Item = [pscustomobject]@{
            Task        = $Task
            Shell       = $Shell
            TabSession  = [pscustomobject]@{ Id = $TabId }
            Description = $Description
            IsCancelled = $false
        }
        if ($null -ne $StartedUtc) {
            $Item | Add-Member -NotePropertyName StartedUtc -NotePropertyValue $StartedUtc
        }
        return $Item
    }

    # Stands in for the worker's [powershell] instance and records what was done to it, so the test
    # asserts the calls rather than racing a real pipeline's state transitions.
    function script:New-FakeShell {
        param([switch]$ThrowOnStop)
        $Shell = [pscustomobject]@{ Stopped = $false; Disposed = $false; ThrowOnStop = [bool]$ThrowOnStop }
        $Shell | Add-Member -MemberType ScriptMethod -Name BeginStop -Value {
            param($Callback, $State)
            if ($this.ThrowOnStop) { throw [System.ObjectDisposedException]::new("PowerShell") }
            $this.Stopped = $true
        }
        $Shell | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed = $true }
        return $Shell
    }
}

Describe "Get-E2EInFlightRequest" {
    It "returns only items carrying StartedUtc" {
        $Queue = [System.Collections.Generic.List[object]]::new()
        $Request = New-QueueItem
        $Queue.Add($Request)
        $Queue.Add((New-QueueItem -StartedUtc $null))

        $Result = @(Get-E2EInFlightRequest -Pending $Queue)

        $Result.Count | Should -Be 1
        $Result[0] | Should -Be $Request
    }

    It "returns nothing for a null queue" {
        @(Get-E2EInFlightRequest -Pending $null).Count | Should -Be 0
    }
}

Describe "Format-E2EInFlightRequest" {
    It "names the description, tab, age and worker state of every request in flight" {
        $Now = [DateTime]::new(2026, 11, 24, 14, 14, 0, [DateTimeKind]::Utc)
        $Queue = [System.Collections.Generic.List[object]]::new()
        $Queue.Add((New-QueueItem -Description "Loading schema" -TabId "tab-1" -StartedUtc $Now.AddSeconds(-15.25)))
        $Queue.Add((New-QueueItem -Description "Executing query" -TabId "tab-2" -StartedUtc $Now.AddSeconds(-3) -Finished))

        $Text = Format-E2EInFlightRequest -Request $Queue -NowUtc $Now

        $Text | Should -BeLike "*'Loading schema' on tab tab-1 for 15*s (worker finished: False)*"
        $Text | Should -BeLike "*'Executing query' on tab tab-2 for 3*s (worker finished: True)*"
    }

    It "does not fail on an item with no tab or description" {
        $Item = New-QueueItem -Description ""
        $Item.TabSession = $null

        Format-E2EInFlightRequest -Request @($Item) | Should -BeLike "'<no description>' on tab <none>*"
    }

    It "ignores editor tasks" {
        Format-E2EInFlightRequest -Request @(New-QueueItem -StartedUtc $null) | Should -BeNullOrEmpty
    }
}

Describe "Clear-E2EInFlightRequest" {
    It "evicts in-flight requests, marks them cancelled and leaves editor tasks queued" {
        $Queue = [System.Collections.Generic.List[object]]::new()
        $Request = New-QueueItem
        $EditorTask = New-QueueItem -StartedUtc $null
        $Queue.Add($Request)
        $Queue.Add($EditorTask)

        $Evicted = @(Clear-E2EInFlightRequest -Pending $Queue)

        $Evicted.Count | Should -Be 1
        $Request.IsCancelled | Should -BeTrue
        $Queue.Count | Should -Be 1
        $Queue[0] | Should -Be $EditorTask
    }

    It "stops and disposes a running worker" {
        $Queue = [System.Collections.Generic.List[object]]::new()
        $Request = New-QueueItem -Shell (New-FakeShell)
        $Queue.Add($Request)

        $null = Clear-E2EInFlightRequest -Pending $Queue

        $Queue.Count | Should -Be 0
        $Request.Shell.Stopped | Should -BeTrue
        $Request.Shell.Disposed | Should -BeTrue
    }

    It "still empties the queue when stopping a shell throws" {
        $Queue = [System.Collections.Generic.List[object]]::new()
        $Request = New-QueueItem -Shell (New-FakeShell -ThrowOnStop)
        $Queue.Add($Request)

        { Clear-E2EInFlightRequest -Pending $Queue } | Should -Not -Throw
        $Queue.Count | Should -Be 0
    }
}
