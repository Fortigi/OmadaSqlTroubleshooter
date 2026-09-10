#Requires -Version 7.0
# Tests for collecting a background request's outcome on the UI thread (issue #40).
#
# These run against REAL [powershell] pipelines rather than stubs, because the two behaviours that
# matter here are behaviours of PowerShell itself:
#   - EndInvoke on a pipeline that was stopped THROWS, so the cancelled case must be detected before
#     EndInvoke is called and not caught afterwards;
#   - the core's hashtable arrives wrapped in the pipeline's output collection.
# A stubbed shell would let either of those regress silently.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Complete-OmadaBackgroundRequest.ps1")

    function script:New-TestPending {
        param(
            [scriptblock]$Body,
            [switch]$Cancelled
        )
        $Shell = [powershell]::Create()
        [void]$Shell.AddScript($Body)
        $Async = $Shell.BeginInvoke()
        return [pscustomobject]@{
            Task        = $Async
            Shell       = $Shell
            IsCancelled = [bool]$Cancelled
            Description = "test request"
        }
    }

    function script:Wait-TestPending {
        param($Pending, [int]$TimeoutMs = 10000)
        $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
        while (-not $Pending.Task.IsCompleted -and [DateTime]::UtcNow -lt $Deadline) {
            Start-Sleep -Milliseconds 20
        }
    }
}

Describe "Complete-OmadaBackgroundRequest" {
    It "unwraps the core's contract out of the pipeline output" {
        $Pending = New-TestPending -Body { return @{ Result = [pscustomobject]@{ d = "schema" }; ErrorRecord = $null } }
        Wait-TestPending -Pending $Pending

        $Outcome = Complete-OmadaBackgroundRequest -Pending $Pending

        $Outcome.Result.d | Should -Be "schema"
        $Outcome.ErrorRecord | Should -BeNullOrEmpty
        $Outcome.IsCancelled | Should -BeFalse
    }

    It "carries a returned ErrorRecord through unchanged" {
        $Pending = New-TestPending -Body {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("transport failed"), "OmadaTransportFailure",
                [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
            return @{ Result = $null; ErrorRecord = $ErrorRecord }
        }
        Wait-TestPending -Pending $Pending

        $Outcome = Complete-OmadaBackgroundRequest -Pending $Pending

        $Outcome.Result | Should -BeNullOrEmpty
        $Outcome.ErrorRecord.Exception.Message | Should -Be "transport failed"
    }

    It "reports a cancelled request as cancelled, with neither a result nor an error" {
        # Nothing failed - the caller stopped waiting. Reporting an error here would put an error
        # dialog in front of a user who had just clicked Cancel.
        $Pending = New-TestPending -Body { Start-Sleep -Seconds 30; return @{ Result = "late"; ErrorRecord = $null } }
        Start-Sleep -Milliseconds 150
        $Pending.Shell.BeginStop($null, $null) | Out-Null
        $Pending.IsCancelled = $true
        Wait-TestPending -Pending $Pending

        $Outcome = Complete-OmadaBackgroundRequest -Pending $Pending

        $Outcome.IsCancelled | Should -BeTrue
        $Outcome.Result | Should -BeNullOrEmpty
        $Outcome.ErrorRecord | Should -BeNullOrEmpty
    }

    It "does not throw when EndInvoke would - a stopped pipeline that was not marked cancelled" {
        # The defensive half of the case above: EndInvoke on a stopped pipeline throws, and this
        # function must turn that into a reported failure rather than an exception escaping into the
        # completion poll timer.
        $Pending = New-TestPending -Body { Start-Sleep -Seconds 30 }
        Start-Sleep -Milliseconds 150
        $Pending.Shell.BeginStop($null, $null) | Out-Null
        Wait-TestPending -Pending $Pending

        { Complete-OmadaBackgroundRequest -Pending $Pending } | Should -Not -Throw
    }

    It "surfaces the worker's error stream when the worker returned nothing usable" {
        $Pending = New-TestPending -Body { Write-Error "worker blew up"; return "not the contract" }
        Wait-TestPending -Pending $Pending

        $Outcome = Complete-OmadaBackgroundRequest -Pending $Pending

        $Outcome.Result | Should -BeNullOrEmpty
        $Outcome.ErrorRecord | Should -Not -BeNullOrEmpty
        [string]$Outcome.ErrorRecord | Should -Match "worker blew up"
    }

    It "disposes the shell so a stopped worker's runspace is never reused" {
        # A pipeline killed mid-request leaves a half-read HTTP stream and a WebRequestSession in an
        # unknown state, so its runspace must be discarded rather than handed to the next query.
        # Disposing is what releases it - and a disposed [powershell] refuses further invocation.
        $Pending = New-TestPending -Body { return @{ Result = "ok"; ErrorRecord = $null } }
        Wait-TestPending -Pending $Pending

        Complete-OmadaBackgroundRequest -Pending $Pending | Out-Null

        { $Pending.Shell.AddScript({ 1 }) } | Should -Throw
    }
}
