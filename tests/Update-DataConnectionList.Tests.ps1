#Requires -Version 7.0
# Issue #90, slice A. Update-DataConnectionList was the worst of the blocking list refreshes - three
# dependent round-trips on the UI thread, on connect and on tab materialisation.
#
# What is asserted here is the DECISION: dispatch or run inline, and which of the four outcomes the
# completion turns into which UI action. The rendering itself (Complete-DataConnectionListUpdate)
# creates WPF ComboBoxItems and so cannot run headlessly on CI; it is stubbed, and the E2E suite
# covers the real thing.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Get-SqlTroubleShooterView.ps1")
    . (Join-Path $PrivatePath -ChildPath "Update-DataConnectionList.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    # Real, not stubbed: what a worker failure MEANS is this function's decision, and the whole point
    # of asking it is that the view lookup must not re-decide. A stub here would let the two drift
    # apart silently - which is the misclassification it exists to prevent.
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaHttpStatusCode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaSessionExpiredError.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-ExecuteFallbackAction.ps1")

    # The shape a worker's HTTP failure actually arrives in: flattened across the runspace boundary,
    # with the code recoverable from the message text. Get-OmadaHttpStatusCode reads it either way.
    function script:New-HttpErrorRecord {
        param([int]$StatusCode, [string]$Message)
        return [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(("Response status code does not indicate success: {0} ({1})." -f $StatusCode, $Message)),
            "x", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
    }

    function ConvertTo-RedactedLogString { param($InputObject, $MaxDepth, [switch]$ShapeOnly) return "<redacted>" }
    function Test-ConnectionRequirements { return $script:ConnectionReady }
    function Get-ActiveTabSession { return $script:ActiveTab }
    function Disable-OmadaBackgroundRequest { param($Reason) $script:DisabledReason = $Reason }
    function Write-ExecutePipelineLog { param($Log) $script:ReplayedLog = $Log }
    function Write-ContainedErrorLog { param([Parameter(ValueFromPipeline = $true)]$InputObject, $ErrorObject) process { } }

    # The rendering, stubbed: it creates WPF ComboBoxItems, which CI's headless pwsh cannot resolve.
    # Recorded rather than performed, so the tests assert what it was ASKED to do.
    $script:Rendered = [System.Collections.Generic.List[object]]::new()
    function Complete-DataConnectionListUpdate {
        param($DataObjectHtml, [switch]$HasRows, [switch]$NotShowPopupWindow)
        $script:Rendered.Add([pscustomobject]@{
                Html               = $DataObjectHtml
                HasRows            = [bool]$HasRows
                NotShowPopupWindow = [bool]$NotShowPopupWindow
                TabId              = $Script:ActiveTabIdForTest
            })
    }

    # The inline path's two halves.
    function Get-SqlTroubleShooterView { $script:InlineViewCalls++; return $script:InlineViewRows }
    function Invoke-OmadaPSWebRequestWrapper { $script:InlinePageCalls++; return $script:InlinePage }

    # Dispatch, stubbed: records what was asked for and hands back the completion block so a test can
    # drive it with any outcome. $null models "not dispatched".
    function Invoke-OmadaPSWebRequestWrapperAsync {
        param([scriptblock]$OnResultScriptBlock, $Context, [hashtable]$PipelineContext, [string]$Description)
        $script:Dispatched = [pscustomobject]@{
            Description     = $Description
            Context         = $Context
            PipelineContext = $PipelineContext
            OnResult        = $OnResultScriptBlock
        }
        if (-not $script:WorkerAvailable) {
            return $null
        }
        return [pscustomobject]@{ Description = $Description; Context = @{ Caller = $Context }; TabSession = $script:ActiveTab }
    }

    function script:Initialize-TestState {
        $script:LogMessages.Clear()
        $script:Rendered.Clear()
        $script:ConnectionReady = $true
        $script:WorkerAvailable = $true
        $script:Dispatched = $null
        $script:DisabledReason = $null
        $script:ReplayedLog = $null
        $script:InlineViewCalls = 0
        $script:InlinePageCalls = 0
        $script:InlineViewRows = @([pscustomobject]@{ C_SQLQUERYDOID = "inline-doid" })
        $script:InlinePage = "<html>inline page</html>"
        $script:ActiveTab = [pscustomobject]@{ Id = "tab-1" }
        $Script:ActiveTabIdForTest = "tab-1"
        $Script:ConnectionStatus = $true
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $Script:AppConfig = [pscustomobject]@{ BaseUrl = "https://tenant.omada.cloud" }
        $Script:RunTimeData = [pscustomobject]@{
            RestMethodParam                 = @{ SessionKey = "tab-1" }
            DataobjdlgAspxAttributeMapping  = [pscustomobject]@{ SqlQueryDoId = "C_SQLQUERYDOID" }
        }
    }

    # Drives the REAL chain: the block registered on the queue is Start-SqlTroubleShooterViewLookup's
    # own completion, which classifies the worker's outcome and then calls the caller's block. Tests
    # hand it a pipeline outcome, exactly as the poll timer would, rather than short-circuiting to
    # the caller's block and proving nothing about the classification.
    function script:Invoke-Completion {
        param($Outcome, $Dispatch = $script:Dispatched)
        & $Dispatch.OnResult ([pscustomobject]@{
                Outcome = $Outcome
                Context = @{ Caller = $Dispatch.Context }
            })
    }

    function script:New-WorkerOutcome {
        param($Rows = @(), $DataObjectHtml = $null, $CompletedSteps = 3, $ErrorMessage = $null)
        return @{
            Rows           = $Rows
            DataObjectHtml = $DataObjectHtml
            CompletedSteps = $CompletedSteps
            Log            = @()
            ErrorRecord    = $(if ($null -eq $ErrorMessage) { $null } else {
                    [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($ErrorMessage), "x", "NotSpecified", $null)
                })
        }
    }
}

Describe "Update-DataConnectionList" {
    BeforeEach { Initialize-TestState }

    Context "Choosing between a worker and the UI thread" {
        It "does not touch the tenant when the connection is not ready" {
            $script:ConnectionReady = $false

            Update-DataConnectionList

            $script:Dispatched | Should -BeNullOrEmpty
            $script:InlineViewCalls | Should -Be 0
        }

        It "dispatches one job, not three requests" {
            # The whole point of the slice: three round-trips, one completion.
            Update-DataConnectionList

            $script:Dispatched.PipelineContext.PipelineFunction | Should -Be "Invoke-OmadaViewLookupPipeline"
            $script:Dispatched.PipelineContext.IncludeDataObjectHtml | Should -BeTrue
        }

        It "does nothing on the UI thread once dispatched" {
            Update-DataConnectionList

            $script:InlineViewCalls | Should -Be 0
            $script:InlinePageCalls | Should -Be 0
            $script:Rendered.Count | Should -Be 0
        }

        It "runs the whole thing inline when no worker is available" {
            # Exactly the pre-#90 behaviour, which is the fallback's entire contract.
            $script:WorkerAvailable = $false

            Update-DataConnectionList

            $script:InlineViewCalls | Should -Be 1
            $script:InlinePageCalls | Should -Be 1
            $script:Rendered[0].Html | Should -Be "<html>inline page</html>"
        }

        It "treats a view that exists but holds no rows as no rows, without throwing" {
            # An empty view comes back as an empty ARRAY, which is not $null, so a null check let it
            # through. Nothing throws (this codebase never enables Set-StrictMode) - it sent a
            # request with no DOID and reported the answer as a failed fetch, which disables the
            # dropdown. Hence the assertion that no page request is made at all.
            $script:WorkerAvailable = $false
            $script:InlineViewRows = @()

            { Update-DataConnectionList } | Should -Not -Throw
            $script:Rendered[0].HasRows | Should -BeFalse
            $script:InlinePageCalls | Should -Be 0
        }

        It "tells the worker which row property holds the data object id" {
            # The attribute mapping is UI-thread state; a worker runspace has none, so it has to
            # travel on the context or the third step opens DOID= nothing.
            Update-DataConnectionList

            $script:Dispatched.PipelineContext.SqlQueryDoIdField | Should -Be "C_SQLQUERYDOID"
        }
    }

    Context "What the completion does with each outcome" {
        BeforeEach { Update-DataConnectionList }

        It "renders the page the worker fetched" {
            Invoke-Completion -Outcome (New-WorkerOutcome -Rows @([pscustomobject]@{ Id = 1 }) -DataObjectHtml "<html>worker page</html>")

            $script:Rendered[0].Html | Should -Be "<html>worker page</html>"
            $script:Rendered[0].HasRows | Should -BeTrue
        }

        It "runs the caller's own inline path when the worker could not do the job" {
            # RetryInline rather than a second copy of the inline path inside the lookup helper.
            Invoke-Completion -Outcome (New-WorkerOutcome -CompletedSteps 0 -ErrorMessage "no session")

            $script:InlineViewCalls | Should -Be 1
            $script:InlinePageCalls | Should -Be 1
            $script:Rendered[0].Html | Should -Be "<html>inline page</html>"
        }

        It "reports no rows as no rows, not as a failed page fetch" {
            # The distinction the original code made and that both arrive here as a null page: a view
            # with no rows left the dropdown untouched and said nothing, a FAILED fetch warned and
            # disabled the controls.
            Invoke-Completion -Outcome (New-WorkerOutcome -Rows @() -CompletedSteps 2)

            $script:Rendered[0].HasRows | Should -BeFalse
        }

        It "carries this call's popup preference, not whatever the active tab wants now" {
            Initialize-TestState
            Update-DataConnectionList -NotShowPopupWindow

            Invoke-Completion -Outcome (New-WorkerOutcome -Rows @([pscustomobject]@{ Id = 1 }) -DataObjectHtml "<html>x</html>")

            $script:Rendered[0].NotShowPopupWindow | Should -BeTrue
        }
    }
}

Describe "Start-SqlTroubleShooterViewLookup" {
    BeforeEach { Initialize-TestState }

    Context "When a lookup is already in flight" {
        BeforeEach {
            $script:Outstanding = [pscustomobject]@{
                Description = $Script:SqlTroubleShooterViewRequestDescription
                TabSession  = [pscustomobject]@{ Id = "tab-1" }
                Context     = @{ Caller = @{ IncludeDataObjectHtml = $false } }
            }
            $Script:PendingWebViewCompletions.Add($script:Outstanding)
        }

        It "does not ask for the same lookup twice for one tab" {
            $null = Start-SqlTroubleShooterViewLookup -OnResultScriptBlock { } -Context @{}

            $script:Dispatched | Should -BeNullOrEmpty
        }

        It "returns the outstanding request, NEVER null" {
            # $null is this function's "not dispatched, do what you did before" answer, and the
            # caller's "before" is the three blocking round-trips this slice exists to remove.
            # Answering $null here would defeat the guard AND put the freeze back - worse than the
            # duplicate request the guard was meant to prevent.
            $Private:Pending = Start-SqlTroubleShooterViewLookup -OnResultScriptBlock { } -Context @{}

            $Private:Pending | Should -Not -BeNullOrEmpty
            $Private:Pending | Should -Be $script:Outstanding
        }

        It "does ask when the outstanding lookup belongs to another tab" {
            # Per tab, not per session: each tab has its own connection and its own dropdown to fill.
            $script:Outstanding.TabSession = [pscustomobject]@{ Id = "tab-2" }

            $null = Start-SqlTroubleShooterViewLookup -OnResultScriptBlock { } -Context @{}

            $script:Dispatched | Should -Not -BeNullOrEmpty
        }

        It "does ask when the outstanding lookup is a different shape" {
            # A lookup running WITHOUT the data connection page cannot satisfy a caller that needs
            # it: joining would leave that caller waiting for data the worker was never asked to
            # fetch. This is the case slice B creates, where Update-QueryList wants the rows only.
            $null = Start-SqlTroubleShooterViewLookup -IncludeDataObjectHtml -OnResultScriptBlock { } -Context @{}

            $script:Dispatched | Should -Not -BeNullOrEmpty
            $script:Dispatched.PipelineContext.IncludeDataObjectHtml | Should -BeTrue
        }
    }

    It "records its shape, so the in-flight guard can compare it" {
        $null = Start-SqlTroubleShooterViewLookup -IncludeDataObjectHtml -OnResultScriptBlock { } -Context @{}

        $script:Dispatched.Context.IncludeDataObjectHtml | Should -BeTrue
    }

    It "does not run the blocking path when it joins an outstanding request" {
        # The whole point, end to end: a second Update-DataConnectionList while one is in flight must
        # not reach the UI thread's three round-trips.
        Update-DataConnectionList
        $Script:PendingWebViewCompletions.Add([pscustomobject]@{
                Description = $Script:SqlTroubleShooterViewRequestDescription
                TabSession  = [pscustomobject]@{ Id = "tab-1" }
                Context     = @{ Caller = @{ IncludeDataObjectHtml = $true } }
            })
        $script:InlineViewCalls = 0
        $script:InlinePageCalls = 0

        Update-DataConnectionList

        $script:InlineViewCalls | Should -Be 0
        $script:InlinePageCalls | Should -Be 0
    }

    It "leaves the third step out when the caller does not want it" {
        $null = Start-SqlTroubleShooterViewLookup -OnResultScriptBlock { } -Context @{}

        $script:Dispatched.PipelineContext.IncludeDataObjectHtml | Should -BeFalse
    }

    Context "Classifying what came back" {
        BeforeEach {
            $script:Received = $null
            $null = Start-SqlTroubleShooterViewLookup -OnResultScriptBlock {
                param($Result, $CallerContext)
                $script:Received = $Result
            } -Context @{}
        }

        It "retries AND disables when the worker produced nothing at all" {
            # No outcome is the only thing that proves a worker cannot serve a request.
            & $script:Dispatched.OnResult ([pscustomobject]@{
                    Outcome = $null
                    Context = @{ Caller = $script:Dispatched.Context }
                })

            $script:Received.RetryInline | Should -BeTrue
            $script:DisabledReason | Should -Not -BeNullOrEmpty
        }

        It "does NOT retry when the tenant answered and then refused" {
            # A tenant that answered will answer the same way again, so retrying inline just costs
            # the user another round-trip.
            & $script:Dispatched.OnResult ([pscustomobject]@{
                    Outcome = @{ ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("forbidden"), "x", "NotSpecified", $null); CompletedSteps = 1; Log = @() }
                    Context = @{ Caller = $script:Dispatched.Context }
                })

            $script:Received.RetryInline | Should -BeFalse
            $script:Received.Rows | Should -BeNullOrEmpty
            $script:DisabledReason | Should -BeNullOrEmpty
        }

        It "does not disable background execution over a first-step HTTP error" {
            # THE regression this classification exists to prevent. A tenant can answer with an HTTP
            # error on the FIRST step, which leaves CompletedSteps at 0 - but a status code proves the
            # worker reached the tenant. Reading that as "the worker is broken" once disabled
            # background execution for a whole session over one transient 502.
            & $script:Dispatched.OnResult ([pscustomobject]@{
                    Outcome = @{ ErrorRecord = (New-HttpErrorRecord -StatusCode 502 -Message "Bad Gateway"); CompletedSteps = 0; Log = @() }
                    Context = @{ Caller = $script:Dispatched.Context }
                })

            $script:DisabledReason | Should -BeNullOrEmpty
            $script:Received.RetryInline | Should -BeFalse
        }

        It "retries a 401 without disabling, because the UI thread can sign in" {
            # Retry, not RetryAndDisable: the session expired, which says nothing about the worker.
            # Once the UI thread has signed in, the worker has a session to inherit.
            & $script:Dispatched.OnResult ([pscustomobject]@{
                    Outcome = @{ ErrorRecord = (New-HttpErrorRecord -StatusCode 401 -Message "Unauthorized"); CompletedSteps = 0; Log = @() }
                    Context = @{ Caller = $script:Dispatched.Context }
                })

            $script:Received.RetryInline | Should -BeTrue
            $script:DisabledReason | Should -BeNullOrEmpty
        }

        It "asks Resolve-ExecuteFallbackAction rather than deciding for itself" {
            # A source assertion, because the defect is a re-implementation rather than a wrong
            # answer: a second copy of this reasoning would pass every behavioural test above on the
            # day it was written and drift from the original afterwards.
            $Private:Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private\Get-SqlTroubleShooterView.ps1") -Raw

            $Private:Source | Should -Match 'Resolve-ExecuteFallbackAction -Outcome'
            $Private:Source | Should -Not -Match 'CompletedSteps -eq 0'
        }

        It "hands the rows and the page over on success" {
            & $script:Dispatched.OnResult ([pscustomobject]@{
                    Outcome = @{ Rows = @([pscustomobject]@{ Id = 5 }); DataObjectHtml = "<html>ok</html>"; ErrorRecord = $null; CompletedSteps = 3; Log = @() }
                    Context = @{ Caller = $script:Dispatched.Context }
                })

            $script:Received.RetryInline | Should -BeFalse
            $script:Received.DataObjectHtml | Should -Be "<html>ok</html>"
            @($script:Received.Rows).Count | Should -Be 1
        }

        It "replays what the worker would have logged" {
            # A worker cannot log. Without the replay, moving these requests off the UI thread would
            # silently cost the application the lines it has always written for them - which for a
            # troubleshooting tool is the point of the tool.
            & $script:Dispatched.OnResult ([pscustomobject]@{
                    Outcome = @{ Rows = @(); ErrorRecord = $null; CompletedSteps = 2; Log = @(@{ Level = "DEBUG"; Text = "QueryUrl: https://x" }) }
                    Context = @{ Caller = $script:Dispatched.Context }
                })

            @($script:ReplayedLog).Count | Should -Be 1
        }
    }
}

Describe "Two tabs with a lookup in flight" {
    # Issue #90's own criterion: every completion resolves against the tab that started the work.
    # Set-ActiveTabContext repoints $Script:MainForm.Elements and friends between dispatch and
    # completion, so a completion that re-reads ambient state renders into whichever tab happens to
    # be on screen.
    BeforeEach { Initialize-TestState }

    It "renders each tab's answer into that tab" {
        # Tab 1 dispatches...
        $Script:ActiveTabIdForTest = "tab-1"
        $script:ActiveTab = [pscustomobject]@{ Id = "tab-1" }
        Update-DataConnectionList
        $Private:TabOneCompletion = $script:Dispatched

        # ...then tab 2 becomes the active context and dispatches its own.
        $Script:ActiveTabIdForTest = "tab-2"
        $script:ActiveTab = [pscustomobject]@{ Id = "tab-2" }
        Update-DataConnectionList -NotShowPopupWindow
        $Private:TabTwoCompletion = $script:Dispatched

        # The poll timer makes the owning tab active before running a completion. Tab 1's lands while
        # tab 2 is on screen, which is the case that used to render into the wrong tab.
        $Script:ActiveTabIdForTest = "tab-1"
        Invoke-Completion -Dispatch $Private:TabOneCompletion -Outcome (New-WorkerOutcome -Rows @([pscustomobject]@{ Id = 1 }) -DataObjectHtml "<html>one</html>")

        $Script:ActiveTabIdForTest = "tab-2"
        Invoke-Completion -Dispatch $Private:TabTwoCompletion -Outcome (New-WorkerOutcome -Rows @([pscustomobject]@{ Id = 2 }) -DataObjectHtml "<html>two</html>")

        $script:Rendered.Count | Should -Be 2
        ($script:Rendered | Where-Object { $_.TabId -eq "tab-1" }).Html | Should -Be "<html>one</html>"
        ($script:Rendered | Where-Object { $_.TabId -eq "tab-2" }).Html | Should -Be "<html>two</html>"
    }

    It "keeps each tab's popup preference with its own completion" {
        # The parameter that would be re-read from ambient state if it were not carried: tab 1 wants
        # the popup, tab 2 does not.
        $script:ActiveTab = [pscustomobject]@{ Id = "tab-1" }
        Update-DataConnectionList
        $Private:TabOne = $script:Dispatched

        $script:ActiveTab = [pscustomobject]@{ Id = "tab-2" }
        Update-DataConnectionList -NotShowPopupWindow
        $Private:TabTwo = $script:Dispatched

        # Out of dispatch order deliberately: nothing guarantees the workers finish in the order they
        # were started.
        Invoke-Completion -Dispatch $Private:TabTwo -Outcome (New-WorkerOutcome -Rows @(1) -DataObjectHtml "<html>two</html>")
        Invoke-Completion -Dispatch $Private:TabOne -Outcome (New-WorkerOutcome -Rows @(1) -DataObjectHtml "<html>one</html>")

        ($script:Rendered | Where-Object { $_.Html -eq "<html>one</html>" }).NotShowPopupWindow | Should -BeFalse
        ($script:Rendered | Where-Object { $_.Html -eq "<html>two</html>" }).NotShowPopupWindow | Should -BeTrue
    }
}
