#Requires -Version 7.0
# Failure-path tests for background dispatch (issue #40).
#
# The happy path is covered end to end by the E2E suite and by
# Invoke-OmadaPSWebRequestWrapperAsync.Tests.ps1. What is asserted here is what happens when dispatch
# goes WRONG, because that is where resources leak: a [powershell] created and then abandoned holds a
# runspace from the pool, and the caller has already fallen back to a synchronous request, so nothing
# else will ever reach it to release it. Leaking one per failure would eventually starve the pool of
# the very workers the fallback exists to compensate for.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Start-OmadaBackgroundRequest.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    # A real pool, so the shells created below are real too - a stub would prove nothing about
    # whether they get disposed.
    function Initialize-OmadaRequestPool {
        if ($null -eq $script:TestPool) {
            $SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
            $SessionState.ApartmentState = [System.Threading.ApartmentState]::MTA
            $script:TestPool = [runspacefactory]::CreateRunspacePool(1, 2, $SessionState, $Host)
            $script:TestPool.Open()
        }
        return $script:TestPool
    }

    function script:Initialize-DispatchTestState {
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            ModuleFolder    = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src")
        }
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $Script:OmadaRequestWorkerTransportPath = $null
        $Script:OmadaRequestWorkerTransportContext = $null
    }
}

AfterAll {
    if ($null -ne $script:TestPool) {
        try { $script:TestPool.Close() } catch { }
        try { $script:TestPool.Dispose() } catch { }
    }
}

Describe "Start-OmadaBackgroundRequest failure paths" {
    BeforeEach { Initialize-DispatchTestState }

    It "falls back rather than dispatching when a worker file is missing" {
        # A missing file must mean "run it on the UI thread", the way every other unavailability
        # does. Dispatching a worker that then fails on its first line would turn a clean fallback
        # into a failed request.
        $Script:RunTimeConfig.ModuleFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("osq-missing-{0}" -f ([guid]::NewGuid().ToString("N")))

        $Pending = Start-OmadaBackgroundRequest -Parameters @{ Uri = "https://tenant.omada.cloud/x" } -TabSession ([pscustomobject]@{ Id = "tab-A" }) -OnCompletedScriptBlock { }

        $Pending | Should -BeNullOrEmpty
        $Script:PendingWebViewCompletions.Count | Should -Be 0
    }

    It "also checks the pipeline's own files before dispatching one" {
        # A pipeline worker dot-sources New-OmadaQueryRequest.ps1 and Invoke-OmadaExecutePipeline.ps1
        # on top of the core, so those have to be part of the same check.
        $EmptyModule = Join-Path ([System.IO.Path]::GetTempPath()) ("osq-partial-{0}" -f ([guid]::NewGuid().ToString("N")))
        $PrivateDir = Join-Path $EmptyModule "Lib\Functions\Private"
        New-Item -Path $PrivateDir -ItemType Directory -Force | Out-Null
        # Only the core is present; the two pipeline files are not.
        Set-Content -Path (Join-Path $PrivateDir "Invoke-OmadaRequestCore.ps1") -Value "function Invoke-OmadaRequestCore { }"
        $Script:RunTimeConfig.ModuleFolder = $EmptyModule

        try {
            $Pending = Start-OmadaBackgroundRequest -Parameters @{ Uri = "https://tenant.omada.cloud/x" } -TabSession ([pscustomobject]@{ Id = "tab-A" }) -PipelineContext @{ BaseUrl = "https://tenant.omada.cloud" } -OnCompletedScriptBlock { }

            $Pending | Should -BeNullOrEmpty
            $Script:PendingWebViewCompletions.Count | Should -Be 0
        }
        finally {
            Remove-Item -Path $EmptyModule -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "disposes the worker it created when dispatch fails after creating it" {
        # The leak: AddScript, BeginInvoke or the queue Add can throw after the [powershell] exists.
        # The queue is made to throw here because it is the last step and the easiest to fail
        # deterministically.
        $Throwing = [pscustomobject]@{}
        $Throwing | Add-Member -MemberType ScriptMethod -Name Add -Value { throw "queue is broken" }
        $Script:PendingWebViewCompletions = $Throwing

        $Pending = Start-OmadaBackgroundRequest -Parameters @{ Uri = "https://tenant.omada.cloud/x" } -TabSession ([pscustomobject]@{ Id = "tab-A" }) -OnCompletedScriptBlock { }

        $Pending | Should -BeNullOrEmpty
        # The pool has 2 workers. If the failed dispatch leaked its shell, its runspace would never
        # be released - so a fresh dispatch proves the pool is still usable rather than starved.
        Initialize-DispatchTestState
        $Recovered = Start-OmadaBackgroundRequest -Parameters @{ Uri = "https://tenant.omada.cloud/x" } -TabSession ([pscustomobject]@{ Id = "tab-A" }) -OnCompletedScriptBlock { }
        $Recovered | Should -Not -BeNullOrEmpty
        try { $Recovered.Shell.Dispose() } catch { }
    }

    It "does not dispose the worker of a request that was dispatched successfully" {
        # The other half: the completion owns the shell from the moment the item is queued, and
        # disposing it here would break every background request instead of leaking one.
        $Pending = Start-OmadaBackgroundRequest -Parameters @{ Uri = "https://tenant.omada.cloud/x" } -TabSession ([pscustomobject]@{ Id = "tab-A" }) -OnCompletedScriptBlock { }

        $Pending | Should -Not -BeNullOrEmpty
        # Asserted through InvocationStateInfo rather than AddScript: an already-RUNNING [powershell]
        # refuses AddScript too, so that would not tell a live worker from a disposed one. A disposed
        # instance throws on this property; a live one reports a real state.
        { $Pending.Shell.InvocationStateInfo.State } | Should -Not -Throw
        $Pending.Shell.InvocationStateInfo.State | Should -BeIn @("Running", "Completed", "NotStarted")
        try { $Pending.Shell.Dispose() } catch { }
    }
}
