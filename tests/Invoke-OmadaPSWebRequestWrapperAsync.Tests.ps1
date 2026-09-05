#Requires -Version 7.0
# The dispatch decision (issue #40).
#
# The single most important property of this function is its FALLBACK contract: it returns $null,
# having done nothing at all, whenever a request may not or cannot go to a worker - and the caller
# then issues it inline exactly as before. A bug here is not "the request was slow", it is "the
# request never happened" or "the request happened twice", so each refusal path is asserted
# individually along with the fact that no dispatch occurred.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Build-OmadaRequestParameter.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaBackgroundRequestEligible.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-OmadaRequestFailure.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaPSWebRequestWrapperAsync.ps1")

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

    function Invoke-OmadaRestMethod {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest)
    }

    function Set-SqlConnectionState { param([bool]$Status = $true) }

    # The real classification is dot-sourced above, and its Unauthorized branch calls Write-Error
    # -ErrorAction Stop - which is exactly the throwing behaviour the finally in the completion block
    # exists to survive. Stubbing it would test nothing.
    function Set-SqlQueryFunctionState { param([bool]$Status = $true) }

    function Get-ActiveTabSession { return $script:StubTabSession }

    # Records what was dispatched and, when asked, completes it immediately so the completion block
    # can be exercised without a runspace. The real dispatcher has its own tests.
    $script:Dispatches = [System.Collections.Generic.List[object]]::new()

    function Start-OmadaBackgroundRequest {
        param(
            [hashtable]$Parameters,
            $TabSession,
            [scriptblock]$OnCompletedScriptBlock,
            $Context,
            [string]$Description
        )
        if ($script:DispatchBehaviour -eq "Unavailable") {
            return $null
        }
        $Pending = [pscustomobject]@{
            Task        = $null
            Shell       = $null
            TabSession  = $TabSession
            Context     = $Context
            Description = $Description
            Parameters  = $Parameters
            IsCancelled = $false
        }
        $script:Dispatches.Add($Pending)
        if ($script:DispatchBehaviour -eq "CompleteInline") {
            & $OnCompletedScriptBlock $Pending
        }
        return $Pending
    }

    function Complete-OmadaBackgroundRequest {
        param($Pending)
        return $script:WorkerOutcome
    }

    function script:Initialize-AsyncTestState {
        param([bool]$Connected = $true, [bool]$SkipRetry = $false, [bool]$ForceAuthentication = $false)

        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test"; UseWebView2Auth = $false }
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://tenant.omada.cloud" }
        $Script:SkipBodyRedaction = $false
        $Script:RunTimeData = [PSCustomObject]@{
            SkipRetryRequest = $SkipRetry
            RestMethodParam  = @{
                Uri                 = "https://tenant.omada.cloud/probe"
                Method              = "GET"
                AuthenticationType  = "Browser"
                ForceAuthentication = $ForceAuthentication
            }
        }
        $Script:ConnectionStatus = $Connected
        $script:StubTabSession = [pscustomobject]@{ Id = "tab-1" }
        $script:DispatchBehaviour = "Dispatch"
        $script:WorkerOutcome = @{ Result = $null; ErrorRecord = $null; IsCancelled = $false }
        $script:Dispatches.Clear()
    }
}

Describe "Invoke-OmadaPSWebRequestWrapperAsync refuses to dispatch" {
    It "returns null and dispatches nothing when the tab is not connected" {
        Initialize-AsyncTestState -Connected $false

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock { } | Should -BeNullOrEmpty
        $script:Dispatches.Count | Should -Be 0
    }

    It "returns null and dispatches nothing when the request forces authentication" {
        Initialize-AsyncTestState -Connected $true -ForceAuthentication $true

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock { } | Should -BeNullOrEmpty
        $script:Dispatches.Count | Should -Be 0
    }

    It "returns null and dispatches nothing when SkipRetryRequest is set" {
        # The synchronous wrapper answers $null for this WITHOUT making a request. Dispatching here
        # would turn a deliberately suppressed request into a real one.
        Initialize-AsyncTestState -SkipRetry $true

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock { } | Should -BeNullOrEmpty
        $script:Dispatches.Count | Should -Be 0
    }

    It "returns null when there is no active tab to attribute the request to" {
        Initialize-AsyncTestState
        $script:StubTabSession = $null

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock { } | Should -BeNullOrEmpty
    }

    It "returns null when no worker could be had" {
        Initialize-AsyncTestState
        $script:DispatchBehaviour = "Unavailable"

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock { } | Should -BeNullOrEmpty
    }
}

Describe "Invoke-OmadaPSWebRequestWrapperAsync dispatches" {
    It "dispatches a prepared request for a connected tab" {
        Initialize-AsyncTestState

        $Pending = Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock { } -Description "probe"

        $Pending | Should -Not -BeNullOrEmpty
        $script:Dispatches.Count | Should -Be 1
        $script:Dispatches[0].Description | Should -Be "probe"
        # Prepared, not raw: Build-OmadaRequestParameter has run over it.
        $script:Dispatches[0].Parameters.ContainsKey("UseWebView2") | Should -BeTrue
    }

    It "carries the caller's context through to the completion block" {
        Initialize-AsyncTestState
        $script:DispatchBehaviour = "CompleteInline"
        $script:WorkerOutcome = @{ Result = "the response"; ErrorRecord = $null; IsCancelled = $false }
        $script:SeenContext = $null

        Invoke-OmadaPSWebRequestWrapperAsync -Context @{ CacheKey = "pool|42" } -OnResultScriptBlock {
            param($Pending)
            $script:SeenContext = $Pending.Context.Caller.CacheKey
        } | Out-Null

        $script:SeenContext | Should -Be "pool|42"
    }

    It "hands the response to the result block as Outcome" {
        Initialize-AsyncTestState
        $script:DispatchBehaviour = "CompleteInline"
        $script:WorkerOutcome = @{ Result = [pscustomobject]@{ d = "payload" }; ErrorRecord = $null; IsCancelled = $false }
        $script:SeenOutcome = $null

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock {
            param($Pending)
            $script:SeenOutcome = $Pending.Outcome
        } | Out-Null

        $script:SeenOutcome.d | Should -Be "payload"
    }

    It "passes an unclassified failure to the result block as an ErrorRecord" {
        # The same contract the synchronous wrapper has: callers test the result with
        # -is [ErrorRecord], so a background failure has to arrive in that shape too.
        Initialize-AsyncTestState
        $script:DispatchBehaviour = "CompleteInline"
        $script:WorkerOutcome = @{
            Result      = $null
            ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("network down"), "OmadaFailure",
                [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
            IsCancelled = $false
        }
        $script:SeenOutcome = $null

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock {
            param($Pending)
            $script:SeenOutcome = $Pending.Outcome
        } | Out-Null

        $script:SeenOutcome | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $script:SeenOutcome.Exception.Message | Should -Be "network down"
    }

    It "does not invoke the result block for a cancelled request" {
        # Nothing failed and nothing succeeded: the caller stopped waiting. Running the result block
        # would bind a null result over a perfectly good previous one.
        Initialize-AsyncTestState
        $script:DispatchBehaviour = "CompleteInline"
        $script:WorkerOutcome = @{ Result = $null; ErrorRecord = $null; IsCancelled = $true }
        $script:ResultBlockRuns = 0

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock {
            param($Pending)
            $script:ResultBlockRuns++
        } | Out-Null

        $script:ResultBlockRuns | Should -Be 0
    }

    It "still runs the result block when the failure classification throws" {
        # The wedge this guards against: Resolve-OmadaRequestFailure THROWS for the two tenant-level
        # failures (Unauthorized, OData endpoint missing). The caller's result block is what closes
        # the "Executing Query..." popup, re-enables the buttons and stops the stopwatch - and the
        # pending item has already been removed from the queue by the poll timer, so if that block is
        # skipped nothing will ever run it. The tab would stay stuck mid-execute after an expired
        # session, which is the worst possible moment for it.
        Initialize-AsyncTestState
        $script:DispatchBehaviour = "CompleteInline"
        $Unauthorized = [System.Management.Automation.ErrorRecord]::new(
            [System.Net.Http.HttpRequestException]::new("denied", $null, [System.Net.HttpStatusCode]::Unauthorized),
            "OmadaUnauthorized", [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)
        $script:WorkerOutcome = @{ Result = $null; ErrorRecord = $Unauthorized; IsCancelled = $false }
        $script:ResultBlockRuns = 0

        # The throw still propagates - that contract is unchanged - so the call is expected to fail.
        try {
            Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock {
                param($Pending)
                $script:ResultBlockRuns++
            } | Out-Null
        }
        catch { }

        $script:ResultBlockRuns | Should -Be 1
    }

    It "hands the result block the ErrorRecord when the classification threw before setting an outcome" {
        Initialize-AsyncTestState
        $script:DispatchBehaviour = "CompleteInline"
        $Unauthorized = [System.Management.Automation.ErrorRecord]::new(
            [System.Net.Http.HttpRequestException]::new("denied", $null, [System.Net.HttpStatusCode]::Unauthorized),
            "OmadaUnauthorized", [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)
        $script:WorkerOutcome = @{ Result = $null; ErrorRecord = $Unauthorized; IsCancelled = $false }
        $script:SeenOutcome = "not set"

        try {
            Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock {
                param($Pending)
                $script:SeenOutcome = $Pending.Outcome
            } | Out-Null
        }
        catch { }

        $script:SeenOutcome | Should -BeOfType [System.Management.Automation.ErrorRecord]
    }

    It "clears ForceAuthentication after a successful background request, as the inline path does" {
        Initialize-AsyncTestState
        $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
        $script:DispatchBehaviour = "CompleteInline"
        $script:WorkerOutcome = @{ Result = "ok"; ErrorRecord = $null; IsCancelled = $false }

        Invoke-OmadaPSWebRequestWrapperAsync -OnResultScriptBlock { } | Out-Null

        $Script:RunTimeData.RestMethodParam.ForceAuthentication | Should -BeFalse
    }
}
