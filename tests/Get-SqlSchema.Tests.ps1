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
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaRestMethodParameter.ps1")
    . (Join-Path $PrivatePath -ChildPath "Build-OmadaRequestParameter.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-OmadaRequestFailure.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaPSWebRequestWrapper.ps1")
    # The request and response lines go through Write-RedactedRequestLog, which asks the log level first.
    . (Join-Path $PrivatePath -ChildPath "Write-RedactedRequestLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")
    # Get-SqlSchemaObject now takes its cache key from the one place that builds it, which is shared
    # with the schema validation pass of issue #61: two copies of that string format would be two
    # chances for the pass to read a different tenant's schema than the editor shows completions for.
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ActiveSqlSchemaModel.ps1")
    # Issue #158 split the response handling into pieces that a second database reuses: the editor
    # model builder, the tree builder, and the database level of the tree. They are dot-sourced for
    # the same reason as everything above - a missing one throws CommandNotFound inside
    # Complete-SqlSchemaRetrieval's own catch, and "nothing was pushed to the editor" then passes for
    # entirely the wrong reason.
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-JavaScriptLiteral.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SqlSchemaEditorModel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Add-SqlSchemaTreeNode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Update-SqlSchemaDatabaseTree.ps1")
    . (Join-Path $PrivatePath -ChildPath "Push-SqlDatabaseNameList.ps1")
    # The completion decides whether to log the schema whole (VERBOSE2 only), and fills every cached
    # database once the window exists - both real, for the reason given above.
    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $PrivatePath -ChildPath "Add-SqlSchemaCachedDatabaseNode.ps1")
    # The schema request runs as a worker chain (Invoke-OmadaSqlSchemaPipeline): its entry in the chain
    # table, the chain itself, and the replay of the log it brings back.
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaPipelineWorkerFunction.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaSqlSchemaPipeline.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ExecutePipelineLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchema.ps1")

    # The dropdown accessor lives in Resolve-SqlStatementTarget.ps1 and refreshes the list from the
    # tenant when it is empty, which is not something this file wants to reach. Stubbed with the two
    # connections the tests below use.
    function Get-DataConnectionOptionText {
        param([switch]$NoRefresh)
        return , @("OISES - 1001572", "Reporting - 1001999")
    }

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
            [switch]$SkipDialog,
            [switch]$TabScoped
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
            [hashtable]$PipelineContext,
            [string]$Description
        )
        $script:DispatchedPipelineContext = $PipelineContext
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
        $Script:SqlSchemaModelCache = @{}
        $Script:SqlSchemaEditorJsonCache = @{}
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

    It "still fetches for any non-empty DoId, so the guard cannot block the connect path" {
        # Issue #165, and the inverse of what this suite briefly asserted. Three cases here demanded
        # that a DoId of 0 or a non-numeric DoId make no request - a stricter gate than
        # IsNullOrWhiteSpace - and that gate broke
        # NoReconnectStartup :: "accepting the reconnect prompt still connects the tab and retrieves
        # its schema", whose own message is "the guard must not block the connect path". A restored tab
        # accepting reconnect does not hold a positive-integer DoId at that moment, so the strict gate
        # turned a wasted request into a missing schema.
        #
        # The junk DoId is filtered where it originates instead - Start-SqlSchemaPreload skips a
        # non-positive DoId from the dropdown, and Get-DataConnectionReferenceList skips a nameless
        # entry. This asserts the request site stays permissive, which is what the connect path needs.
        Initialize-SchemaTestState -Connected $true
        $Script:AppConfig.CurrentDataConnection.DoId = "0"

        Get-SqlSchemaObject

        (Get-OmadaMockRequestLog -UriLike "*GetSqlSchema*").Count | Should -Be 1
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

Describe "Get-SqlSchemaObject for a database other than the active one (issue #158)" {
    # The schema window now holds a node per data connection and the editor completes
    # "[Other].[dbo].", so the same fetch has to serve a database the tab is NOT connected to. What
    # makes that safe is that such a response may touch only its own editor model: the primary
    # setSchema model, the window title and the validation re-trigger all describe the ACTIVE
    # connection, and a second database landing must not speak for them.

    It "pushes setSchemaForDatabase, naming the database" {
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject -DataConnectionDoId "1001999" -DataConnectionName "Reporting"

        $Push = $script:PushedEditorScripts | Where-Object { $_ -like "setSchemaForDatabase(*" } | Select-Object -Last 1
        $Push | Should -Not -BeNullOrEmpty
        $Push | Should -BeLike '*"Reporting"*'
    }

    It "does not push setSchema, which belongs to the connected database" {
        # The discriminating assertion of this whole feature. Overwriting the primary model would
        # make the completion list describe a database the user is not connected to, for every query
        # in the tab - including the ones that never mention another database.
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject -DataConnectionDoId "1001999" -DataConnectionName "Reporting"

        @($script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" }).Count | Should -Be 0
    }

    It "does not re-trigger validation, which describes the active database" {
        Initialize-SchemaTestState -Connected $true
        $script:ValidationRequests = 0

        Get-SqlSchemaObject -DataConnectionDoId "1001999" -DataConnectionName "Reporting"

        $script:ValidationRequests | Should -Be 0
    }

    It "caches under its own key, leaving the active database's cache entry alone" {
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject
        Get-SqlSchemaObject -DataConnectionDoId "1001999" -DataConnectionName "Reporting"

        $Script:SqlSchemaCache.ContainsKey("pool-under-test|1001572") | Should -BeTrue
        $Script:SqlSchemaCache.ContainsKey("pool-under-test|1001999") | Should -BeTrue
    }

    It "serves a cached database with no request at all (criterion 5)" {
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject -DataConnectionDoId "1001999" -DataConnectionName "Reporting"
        Clear-OmadaMockRequestLog
        $script:PushedEditorScripts.Clear()

        Get-SqlSchemaObject -DataConnectionDoId "1001999" -DataConnectionName "Reporting"

        (Get-OmadaMockRequestLog).Count | Should -Be 0
        # Served, not merely skipped: the caller still needs the model, because the editor that
        # asked has none for this database yet.
        @($script:PushedEditorScripts | Where-Object { $_ -like "setSchemaForDatabase(*" }).Count | Should -Be 1
    }

    It "requests the database it was asked for, not the active one" {
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject -DataConnectionDoId "1001999" -DataConnectionName "Reporting"

        $Request = @(Get-OmadaMockRequestLog -UriLike "*GetSqlSchema*")
        $Request.Count | Should -Be 1
        # connectionId off the recorded body, not a substring of it: the log keeps the body as the
        # hashtable that was sent, so a -BeLike against it only ever matches the type name.
        [string]$Request[0].Body.connectionId | Should -Be "1001999"
    }

    It "still pushes setSchema and the database names for the active connection" {
        # The other half of the switch: called the way every pre-#158 caller calls it, nothing about
        # the active path changes - and the editor is told which names are databases so it can ask.
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject

        @($script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" }).Count | Should -Be 1
        $Names = $script:PushedEditorScripts | Where-Object { $_ -like "setDatabaseNames(*" } | Select-Object -Last 1
        $Names | Should -Not -BeNullOrEmpty
        $Names | Should -BeLike "*Reporting*"
        # The active connection's own name, so the editor answers "[OISES]." from setSchema instead
        # of asking for a schema it will never be sent.
        $Names | Should -BeLike '*"OISES"*'
    }

    It "treats an explicit DoId that happens to be the active one as the active database" {
        Initialize-SchemaTestState -Connected $true

        Get-SqlSchemaObject -DataConnectionDoId "1001572" -DataConnectionName "OISES"

        @($script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" }).Count | Should -Be 1
        @($script:PushedEditorScripts | Where-Object { $_ -like "setSchemaForDatabase(*" }).Count | Should -Be 0
    }
}

Describe "Get-SqlSchemaObject - the worker builds the editor JSON and the validation index" {
    # They used to be built on the UI thread when each schema landed: about two seconds per connect on a
    # cloud PC. Invoke-OmadaSqlSchemaPipeline builds them in the worker; the completion only stores them.

    BeforeAll {
        # The failure path switches background requests off before it retries on the UI thread.
        function Disable-OmadaBackgroundRequest { param($Reason) $script:DisabledReason = $Reason }
    }

    BeforeEach {
        Initialize-SchemaTestState -Connected $true
        $script:AsyncDispatchBehaviour = "InvokeInline"
        $script:Response = [pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblX" = @("Id int NOT NULL") } }
        $script:AsyncDispatchOutcome = @{
            IsSqlSchemaPipeline = $true
            Result              = $script:Response
            ErrorRecord         = $null
            EditorJson          = '{"built":{"in-the-worker":[]}}'
            SchemaModel         = "index built in the worker"
            Log                 = @()
        }
    }

    It "dispatches the schema chain" {
        Get-SqlSchemaObject

        $script:DispatchedPipelineContext.PipelineFunction | Should -Be "Invoke-OmadaSqlSchemaPipeline"
        $script:DispatchedPipelineContext.PipelineFiles | Should -Contain "Invoke-OmadaSqlSchemaPipeline.ps1"
    }

    It "caches the response itself, not the pipeline's outcome" {
        Get-SqlSchemaObject

        [object]::ReferenceEquals($Script:SqlSchemaCache["pool-under-test|1001572"], $script:Response) | Should -BeTrue
    }

    It "pushes the JSON the worker built, without building it again" {
        Get-SqlSchemaObject

        $script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" } | Should -BeExactly 'setSchema({"built":{"in-the-worker":[]}});'
    }

    It "keeps the index the worker built for the validation pass" {
        Get-SqlSchemaObject

        $Script:SqlSchemaModelCache["pool-under-test|1001572"] | Should -BeExactly "index built in the worker"
    }

    It "builds them on the UI thread when the worker could not" {
        $script:AsyncDispatchOutcome.EditorJson = $null
        $script:AsyncDispatchOutcome.SchemaModel = $null

        Get-SqlSchemaObject

        $script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" } | Should -BeLike "*tblX*"
        $Script:SqlSchemaModelCache.ContainsKey("pool-under-test|1001572") | Should -BeFalse -Because "the validation pass builds it on demand, as before"
    }

    It "treats a failed pipeline as a failed request" {
        $script:AsyncDispatchOutcome = @{
            IsSqlSchemaPipeline = $true
            Result              = $null
            ErrorRecord         = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("boom"), "x", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
            EditorJson          = $null
            SchemaModel         = $null
            Log                 = @()
        }
        $Script:ConnectionStatus = $true

        Get-SqlSchemaObject

        # As for a plain failure: retried once on the UI thread, which the mock tenant answers.
        (Get-OmadaMockRequestLog -UriLike "*GetSqlSchema*").Count | Should -Be 1
    }
}

Describe "ConvertFrom-SqlSchemaPipelineOutcome" {

    It "passes a plain response through" {
        $Private:Response = [pscustomobject]@{ d = [pscustomobject]@{} }

        $Private:Unwrapped = ConvertFrom-SqlSchemaPipelineOutcome -Outcome $Private:Response

        [object]::ReferenceEquals($Private:Unwrapped.Response, $Private:Response) | Should -BeTrue
        $Private:Unwrapped.EditorJson | Should -BeNullOrEmpty
    }

    It "passes null and an ErrorRecord through" {
        (ConvertFrom-SqlSchemaPipelineOutcome -Outcome $null).Response | Should -BeNullOrEmpty

        $Private:Failure = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("boom"), "x", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
        (ConvertFrom-SqlSchemaPipelineOutcome -Outcome $Private:Failure).Response | Should -BeOfType [System.Management.Automation.ErrorRecord]
    }

    It "replays the pipeline's log" {
        $script:LoggedMessages.Clear()

        ConvertFrom-SqlSchemaPipelineOutcome -Outcome @{ IsSqlSchemaPipeline = $true; Result = $null; ErrorRecord = $null; Log = @(@{ Level = "DEBUG"; Text = "from the worker" }) } | Out-Null

        @($script:LoggedMessages | Where-Object { $_.Message -eq "from the worker" }).Count | Should -Be 1
    }
}

Describe "Complete-SqlSchemaRetrieval - what it does not redo for a cached schema" {
    # A cache hit hands the completion the object that is already cached. Every tab switch, window
    # open and node expand goes through here, and rebuilding the validation index and the editor JSON
    # each time cost half a second and a second per large database on the cloud PC's UI thread.

    BeforeEach {
        Initialize-SchemaTestState -Connected $true
        $script:LoggedMessages.Clear()
        $script:Response = [pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblCustomer" = @("Id int NOT NULL", "Name nvarchar(50)") } }
    }

    It "keeps the validation index when the same response comes back" {
        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"
        $Script:SqlSchemaModelCache["pool-under-test|1001572"] = "index built from it"

        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"

        $Script:SqlSchemaModelCache["pool-under-test|1001572"] | Should -BeExactly "index built from it"
    }

    It "drops the validation index and the editor JSON for a NEW response" {
        # A refresh: the index and the JSON describe the response being replaced.
        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"
        $Script:SqlSchemaModelCache["pool-under-test|1001572"] = "index built from the old one"

        $Private:Fresh = [pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblOrder" = @("Id int") } }
        Complete-SqlSchemaRetrieval -SchemaResponse $Private:Fresh -SchemaCacheKey "pool-under-test|1001572"

        $Script:SqlSchemaModelCache.ContainsKey("pool-under-test|1001572") | Should -BeFalse
        $Script:SqlSchemaEditorJsonCache["pool-under-test|1001572"] | Should -BeLike "*tblOrder*"
        $Script:SqlSchemaEditorJsonCache["pool-under-test|1001572"] | Should -Not -BeLike "*tblCustomer*"
    }

    It "pushes the memoised JSON again for the same response, without rebuilding it" {
        # Each tab has its own editor, so the push itself still happens.
        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"
        $Script:SqlSchemaEditorJsonCache["pool-under-test|1001572"] = '{"memo":{"marker":[]}}'
        $script:PushedEditorScripts.Clear()

        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"

        $script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" } | Should -BeExactly 'setSchema({"memo":{"marker":[]}});'
    }
}

Describe "Complete-SqlSchemaRetrieval - logging the schema" {
    # Whole at VERBOSE, the schema was 30,000+ lines per large database, a quarter of a second each on
    # the UI thread, and every table and column name in a log a user can export (issue #61 section 5).

    BeforeEach {
        Initialize-SchemaTestState -Connected $true
        $script:LoggedMessages.Clear()
        $script:Response = [pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblCustomer" = @("Id int NOT NULL"); "dbo.tblOrder" = @("Id int") } }
    }

    It "logs only the size at VERBOSE" {
        $Script:RunTimeConfig | Add-Member -NotePropertyName Logging -NotePropertyValue ([pscustomobject]@{ LogLevelSetting = "VERBOSE" }) -Force

        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"

        $Private:Verbose = @($script:LoggedMessages | Where-Object { $_.LogType -eq "VERBOSE" -and $_.Message -like "Schema for Monaco editor*" })
        $Private:Verbose.Count | Should -Be 1
        $Private:Verbose[0].Message | Should -BeLike "*2 table(s)*character(s)*"
        $Private:Verbose[0].Message | Should -Not -BeLike "*tblCustomer*"
        @($script:LoggedMessages | Where-Object { $_.LogType -eq "VERBOSE2" }).Count | Should -Be 0
    }

    It "logs the schema itself at VERBOSE2" {
        $Script:RunTimeConfig | Add-Member -NotePropertyName Logging -NotePropertyValue ([pscustomobject]@{ LogLevelSetting = "VERBOSE2" }) -Force

        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"

        $Private:Full = @($script:LoggedMessages | Where-Object { $_.LogType -eq "VERBOSE2" -and $_.Message -like "Schema for Monaco editor*" })
        $Private:Full.Count | Should -Be 1
        $Private:Full[0].Message | Should -BeLike "*tblCustomer*"
    }

    It "does not fail when no log level is configured" {
        Complete-SqlSchemaRetrieval -SchemaResponse $script:Response -SchemaCacheKey "pool-under-test|1001572"

        @($script:PushedEditorScripts | Where-Object { $_ -like "setSchema(*" }).Count | Should -Be 1
    }
}

Describe "Complete-SqlSchemaRetrieval - the schema window" {
    # Opening the window runs the active database's completion; every other database whose schema the
    # preload already cached is filled then, so the search covers them from the start.

    BeforeAll {
        # Not loaded in this file; the filter has its own suite.
        function Update-SqlSchemaTreeFilter { }
    }

    BeforeEach {
        Initialize-SchemaTestState -Connected $true
        $Script:SqlSchemaForm = [pscustomobject]@{ Definition = [pscustomobject]@{ Title = "" } }
        $Script:TreeViewSqlSchema = [pscustomobject]@{ Items = [System.Collections.Generic.List[object]]::new() }

        # The tree itself is WPF; its own suites cover it. Here only the calls are counted.
        Mock Update-SqlSchemaDatabaseTree { }
        Mock Get-SqlSchemaDatabaseNode { return $null }
        Mock Add-SqlSchemaCachedDatabaseNode { return 0 }
    }

    AfterEach {
        $Script:SqlSchemaForm = $null
        $Script:TreeViewSqlSchema = $null
    }

    It "fills every cached database when the window's schema lands" {
        Complete-SqlSchemaRetrieval -SchemaResponse ([pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblX" = @("Id int") } }) -SchemaCacheKey "pool-under-test|1001572"

        Should -Invoke Add-SqlSchemaCachedDatabaseNode -Times 1 -Exactly
    }

    It "does not touch the tree when the window is not open" {
        $Script:SqlSchemaForm = $null
        $Script:TreeViewSqlSchema = $null

        Complete-SqlSchemaRetrieval -SchemaResponse ([pscustomobject]@{ d = [pscustomobject]@{ "dbo.tblX" = @("Id int") } }) -SchemaCacheKey "pool-under-test|1001572"

        Should -Invoke Add-SqlSchemaCachedDatabaseNode -Times 0 -Exactly
    }
}
