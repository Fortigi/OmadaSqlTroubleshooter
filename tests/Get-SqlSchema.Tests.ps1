#Requires -Version 7.0
# Regression tests for issue #64: Get-SqlSchemaObject must not authenticate against the tenant for a
# tab that is not connected. It runs from the WebView2 NavigationCompleted handler for EVERY tab that
# loads its Monaco editor - including a restored tab that was deliberately left disconnected by
# -NoReconnect or by a declined reconnect prompt - so an unguarded call there is a silent connect.
#
# The request path is exercised end to end through the REAL Invoke-OmadaPSWebRequestWrapper and the
# mock transport shim against a running mock Omada instance, so "zero requests" means zero requests
# actually reached the mock, not "a stub was not called".

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-ConnectionRequirements.ps1")
    # Issue #40 split the wrapper: the request itself into Invoke-OmadaRequestCore, and the
    # preparation and failure classification into these two. All are dot-sourced for the same reason
    # the Suspend/Resume stubs below exist - a missing one throws CommandNotFound inside
    # Get-SqlSchemaObject's own catch, and the "zero requests" assertion then passes for entirely the
    # wrong reason.
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaRequestCore.ps1")
    . (Join-Path $PrivatePath -ChildPath "Build-OmadaRequestParameter.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-OmadaRequestFailure.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaPSWebRequestWrapper.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchema.ps1")

    . (Join-Path $PSScriptRoot -ChildPath "mock\OmadaMockRouter.ps1")
    . (Join-Path $PSScriptRoot -ChildPath "mock\OmadaMockServer.ps1")
    . (Join-Path $PSScriptRoot -ChildPath "mock\Install-OmadaMockTransport.ps1")

    $script:Handle = New-OmadaMockServerHandle -BindAddress "127.0.0.1" -Port 0
    Install-OmadaMockTransport -MockBaseUrl $script:Handle.BaseUrl

    # --- Stubs for everything outside the function under test --------------------------------------
    $Script:Tracer = [System.Diagnostics.Trace]

    # Records what was logged, and crucially at what level and whether a dialog was suppressed: the
    # start-up pop-up cascade this file now guards against was a matter of level, not of message.
    $script:LoggedMessages = [System.Collections.Generic.List[object]]::new()

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process {
            $script:LoggedMessages.Add([pscustomobject]@{
                    LogType    = $LogType
                    Message    = [string]$InputObject
                    SkipDialog = [bool]$SkipDialog
                })
        }
    }

    # The real wrapper suspends the WebView2 completion poll timer around every call; there is no
    # timer here, so both ends are no-ops. Without them the wrapper would throw CommandNotFound and
    # a "no request was made" assertion would pass for the wrong reason.
    function Suspend-WebViewCompletionPolling { }

    function Resume-WebViewCompletionPolling { }

    # The editor push seam. Recorded rather than executed so the connected case can be proven to
    # have reached setSchema(...).
    $script:PushedEditorScripts = [System.Collections.Generic.List[string]]::new()
    # The completion block is captured, not invoked: the tests below drive it with the queue item the
    # real poll timer would pass, which is the whole point of the regression they guard.
    $script:PushedCompletionBlocks = [System.Collections.Generic.List[scriptblock]]::new()

    function Invoke-ExecuteScriptAsync {
        param(
            $ScriptToExecute,
            $OnCompletedScriptBlock
        )
        $script:PushedEditorScripts.Add([string]$ScriptToExecute)
        if ($null -ne $OnCompletedScriptBlock) {
            $script:PushedCompletionBlocks.Add($OnCompletedScriptBlock)
        }
    }

    # A schema push also re-triggers the debounced syntax validation (issue #61): a new connection
    # can invalidate the diagnostics already on screen. Recorded rather than executed - the timer it
    # would restart lives in MainForm.Definition.ps1 and there is no window here.
    $script:ValidationRequests = 0

    function Request-SqlSyntaxValidation {
        param($TabSession)
        $script:ValidationRequests++
    }

    function Get-ActiveTabSession { return $null }

    # The background dispatch seam (issue #40). Its own behaviour is covered by
    # Test-OmadaBackgroundRequestEligible.Tests.ps1 and Complete-OmadaBackgroundRequest.Tests.ps1;
    # here it is steered so this file can test both of Get-SqlSchemaObject's paths deliberately
    # rather than depending on whether a worker happened to be available.
    #
    #   $null              => not dispatched, so the function falls back to the synchronous wrapper.
    #                         This is the default, and it is what keeps the guard tests below
    #                         measuring real requests against the real mock instance.
    #   "InvokeInline"     => dispatched and completed immediately, so the completion block runs -
    #                         which is how the wiring from a background response through to
    #                         Complete-SqlSchemaRetrieval is exercised without a runspace.
    $script:AsyncDispatchBehaviour = "Fallback"

    function Invoke-OmadaPSWebRequestWrapperAsync {
        param(
            [scriptblock]$OnResultScriptBlock,
            $Context,
            [string]$Description
        )
        if ($script:AsyncDispatchBehaviour -ne "InvokeInline") {
            return $null
        }
        $Pending = [pscustomobject]@{
            Description = $Description
            Context     = @{ Caller = $Context; OnResult = $OnResultScriptBlock }
            Outcome     = $script:AsyncDispatchOutcome
        }
        & $OnResultScriptBlock $Pending
        return $Pending
    }

    function Initialize-SchemaTestState {
        <#
        Puts the module-scope state into the shape a RESTORED tab has: a tenant URL and an
        authentication option filled in, a data connection DoId carried over from config, and
        ReconnectStatus already at 3 (the NavigationCompleted handler sets it there as soon as any
        tab's editor has loaded). Every gate Get-SqlSchemaObject had BEFORE the fix is therefore
        satisfied - the connection flag is the only thing that separates the two cases.
        #>
        param(
            [bool]$Connected
        )

        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test"; ReconnectStatus = 3 }
        $Script:AppConfig = [PSCustomObject]@{
            BaseUrl               = "https://tenant.omada.cloud"
            CurrentDataConnection = [PSCustomObject]@{ DoId = "1001572"; FullName = "OISES - 1001572" }
        }
        $Script:RunTimeData = @{
            SkipRetryRequest = $false
            SqlQueryObject   = $null
            RestMethodParam  = @{
                SessionKey          = "pool-under-test"
                AuthenticationType  = "Browser"
                ForceAuthentication = $false
            }
        }
        $Script:MainForm = @{
            Elements = @{
                TextBoxURL                          = [PSCustomObject]@{ Text = "https://tenant.omada.cloud" }
                ComboBoxSelectAuthenticationOption  = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Content = "Browser" } }
            }
        }
        # No schema window in these tests: Get-SqlSchemaObject must skip the TreeView/title work and
        # still push to the editor.
        $Script:SqlSchemaForm = $null
        $Script:TreeViewSqlSchema = $null
        $Script:SqlSchemaCache = @{}
        $Script:ConnectionStatus = $Connected

        $script:PushedEditorScripts.Clear()
        $script:AsyncDispatchBehaviour = "Fallback"
        $script:AsyncDispatchOutcome = $null
        Clear-OmadaMockRequestLog
    }
}

AfterAll {
    if ($null -ne $script:Handle) { Stop-OmadaMockServerHandle -Handle $script:Handle }
}

Describe "Get-SqlSchemaObject connection guard" {
    It "makes no request at all when the tab is not connected" {
        Initialize-SchemaTestState -Connected $false

        Get-SqlSchemaObject

        (Get-OmadaMockRequestLog).Count | Should -Be 0
        $script:PushedEditorScripts.Count | Should -Be 0
    }

    It "does not connect even though every pre-fix gate is satisfied" {
        Initialize-SchemaTestState -Connected $false

        # Discriminating: these are exactly the three conditions the function used to rely on. All
        # three say "go", and the request must still not happen.
        $Script:RunTimeConfig.ReconnectStatus | Should -Not -Be 1
        Test-ConnectionRequirements | Should -BeTrue
        $Script:AppConfig.CurrentDataConnection.DoId | Should -Not -BeNullOrEmpty

        Get-SqlSchemaObject

        (Get-OmadaMockRequestLog -UriLike "*GetSqlSchema*").Count | Should -Be 0
    }

    It "retrieves the schema and pushes it to the editor when the tab is connected" {
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject

        (Get-OmadaMockRequestLog -UriLike "*GetSqlSchema*" -MethodLike "POST").Count | Should -Be 1

        $SetSchema = $script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" } | Select-Object -Last 1
        $SetSchema | Should -Not -BeNullOrEmpty
        $SetSchema | Should -BeLike "*nvarchar*"
    }

    It "serves a second connected call from the per-pool cache without another request" {
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject
        Clear-OmadaMockRequestLog
        Get-SqlSchemaObject

        (Get-OmadaMockRequestLog).Count | Should -Be 0
    }
}

Describe "Get-SqlSchemaObject background dispatch (issue #40)" {
    It "falls back to a synchronous request when nothing was dispatched" {
        # The contract that keeps this change safe: a request that may not, or cannot, go to a worker
        # still happens - it just happens inline, exactly as before.
        Initialize-SchemaTestState -Connected $true
        $script:AsyncDispatchBehaviour = "Fallback"

        Get-SqlSchemaObject

        (Get-OmadaMockRequestLog -UriLike "*GetSqlSchema*" -MethodLike "POST").Count | Should -Be 1
    }

    It "makes no synchronous request when the work was dispatched" {
        # The other half: a dispatched request must not ALSO be issued inline. Getting this wrong
        # would double every schema fetch, silently.
        Initialize-SchemaTestState -Connected $true
        $script:AsyncDispatchBehaviour = "InvokeInline"
        $script:AsyncDispatchOutcome = [pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblX" = @("Id int NOT NULL") } }

        Get-SqlSchemaObject

        (Get-OmadaMockRequestLog -UriLike "*GetSqlSchema*").Count | Should -Be 0
    }

    It "drives the schema through to the editor from a background response" {
        Initialize-SchemaTestState -Connected $true
        $script:AsyncDispatchBehaviour = "InvokeInline"
        $script:AsyncDispatchOutcome = [pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblX" = @("Id int NOT NULL") } }

        Get-SqlSchemaObject

        $SetSchema = $script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" } | Select-Object -Last 1
        $SetSchema | Should -Not -BeNullOrEmpty
        $SetSchema | Should -BeLike "*tblX*"
    }

    It "caches a background response under the key the request was issued for, not a re-derived one" {
        # The completion block reads its cache key from the pending item. Re-deriving it would use
        # whatever tab is active by the time the response lands, which is how a schema ends up filed
        # under - and later served to - the wrong connection.
        Initialize-SchemaTestState -Connected $true
        $script:AsyncDispatchBehaviour = "InvokeInline"
        $script:AsyncDispatchOutcome = [pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblX" = @("Id int NOT NULL") } }

        Get-SqlSchemaObject

        $Script:SqlSchemaCache.ContainsKey("pool-under-test|1001572") | Should -BeTrue
    }

    It "reports a background failure without caching it" {
        Initialize-SchemaTestState -Connected $true
        $script:AsyncDispatchBehaviour = "InvokeInline"
        $script:AsyncDispatchOutcome = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("boom"), "OmadaSchemaFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        Get-SqlSchemaObject

        $Script:SqlSchemaCache.Count | Should -Be 0
        $script:PushedEditorScripts.Count | Should -Be 0
    }
}

Describe "Get-SqlSchemaObject's Monaco push completion" {
    # Regression guard for a cascade of error dialogs when reconnecting several tabs at start-up.
    #
    # The block used to read $Script:Task - the ACTIVE tab's pending editor task - rather than the
    # task of the push it was invoked for. During start-up that is very often a different,
    # still-running task, so it reported "WaitingForActivation" (a perfectly normal transient state)
    # as a failure, at ERROR, which means a modal dialog each time. The poll timer only invokes a
    # completion once its own item's task has completed, so the item's task is the real answer.

    BeforeEach {
        Initialize-SchemaTestState -Connected $true
        $script:PushedCompletionBlocks.Clear()
        # Serve the schema inline so a push - and therefore a completion block - is produced.
        $script:AsyncDispatchBehaviour = "Fallback"
        Get-SqlSchemaObject
        $script:LoggedMessages.Clear()
    }

    It "captures a completion block for the push" {
        $script:PushedCompletionBlocks.Count | Should -BeGreaterThan 0
    }

    It "says nothing at ERROR or WARNING for a push that completed" {
        $Block = $script:PushedCompletionBlocks | Select-Object -Last 1

        & $Block ([pscustomobject]@{ Task = [pscustomobject]@{ Status = "RanToCompletion" } })

        @($script:LoggedMessages | Where-Object { $_.LogType -in @("ERROR", "WARNING") }).Count | Should -Be 0
    }

    It "reads the task from the queue item, not from the active tab" {
        # The discriminating case: the ACTIVE tab's task is mid-flight while the item's own task
        # finished. Reading $Script:Task would report a failure that did not happen - which is
        # exactly what produced the start-up dialogs.
        $Block = $script:PushedCompletionBlocks | Select-Object -Last 1
        $Script:Task = [pscustomobject]@{ Status = "WaitingForActivation" }

        & $Block ([pscustomobject]@{ Task = [pscustomobject]@{ Status = "RanToCompletion" } })

        @($script:LoggedMessages | Where-Object { $_.LogType -in @("ERROR", "WARNING") }).Count | Should -Be 0
    }

    It "reports a genuinely failed push as a WARNING, without a dialog" {
        # Failing to push IntelliSense metadata costs the user completion hints, not their work, so it
        # must never interrupt them with a modal - least of all several at once during start-up.
        $Block = $script:PushedCompletionBlocks | Select-Object -Last 1

        & $Block ([pscustomobject]@{ Task = [pscustomobject]@{ Status = "Faulted" } })

        @($script:LoggedMessages | Where-Object { $_.LogType -eq "ERROR" }).Count | Should -Be 0
        $Warnings = @($script:LoggedMessages | Where-Object { $_.LogType -eq "WARNING" })
        $Warnings.Count | Should -Be 1
        $Warnings[0].SkipDialog | Should -BeTrue
    }

    It "does nothing at all when the queue item carries no task" {
        $Block = $script:PushedCompletionBlocks | Select-Object -Last 1

        { & $Block ([pscustomobject]@{ Task = $null }) } | Should -Not -Throw
        @($script:LoggedMessages | Where-Object { $_.LogType -in @("ERROR", "WARNING") }).Count | Should -Be 0
    }
}
