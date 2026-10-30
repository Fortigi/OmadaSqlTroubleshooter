# The label every validation item on $Script:PendingWebViewCompletions carries, so it can be told apart
# from an execute, a schema fetch or an editor read.
$Script:SqlValidationRequestDescription = "SQL validation"

# tab id -> the validation item still running for that tab. At most one per tab: starting another
# stops the first (Stop-SqlDiagnosticBackground), and a result is applied only while its item is still
# the one registered here (Complete-SqlDiagnosticBackground).
$Script:SqlValidationInFlight = @{}

# What a validation worker runs. The passes are dot-sourced from disk, for the same reason
# Start-OmadaBackgroundRequest does it: one copy of every function, and those files are the ones the
# unit tests execute. Write-LogOutput is replaced by a no-op: the passes only ever log at DEBUG, the
# worker has no log window to write to, and their messages are kept free of query text anyway.
#
# Handed to the worker as text (PowerShell.AddScript), so it runs in the worker's own session state
# and nothing here can be reached from it.
$Script:SqlDiagnosticWorkerScript = {
    param($PrivateFolder, $WorkerFile, $SqlText, $Setting, $SchemaModel, $DatabaseSchemaModel)

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$Message, $LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { }
    }

    foreach ($File in $WorkerFile) {
        . (Join-Path $PrivateFolder $File)
    }

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Result = Get-SqlDiagnostic -SqlText $SqlText -Setting $Setting -SchemaModel $SchemaModel -DatabaseSchemaModel $DatabaseSchemaModel

    return [PSCustomObject]@{
        Result              = $Result
        ElapsedMilliseconds = [long]$Stopwatch.ElapsedMilliseconds
    }
}

# What the poll timer runs on the UI thread once a worker is done, with the pending item as its
# argument. A plain script block, never .GetNewClosure(), for the reason at the top of
# MainForm.Definition.ps1: it must resolve this module's private functions when .NET invokes it.
$Script:SqlDiagnosticCompletionScript = {
    param($Pending)

    $Outcome = Complete-SqlDiagnosticBackground -Pending $Pending
    if ($Outcome.Apply) {
        Invoke-ExecuteScriptAsync -ScriptToExecute (ConvertTo-EditorDiagnosticScript -Diagnostic $Outcome.Diagnostic)
    }
}

function Start-SqlDiagnosticForTab {
    <#
    .SYNOPSIS
        Starts a worker validation of a tab's editor text, with the schema models that tab resolves to.

    .DESCRIPTION
        The models are found HERE, on the UI thread, because only the UI thread may: the active tab's
        model, and the other databases' models found through the data connection dropdown. Both are
        memoised, so this is lookups rather than indexing. With the schema pass off, neither is
        needed and neither is looked up.

        Must be called with $TabSession as the active tab, which is how the debounced path calls it:
        from a completion the poll timer runs with its tab made active.

    .PARAMETER TabSession
        The tab whose editor content this is.

    .PARAMETER SqlText
        The editor content to validate.

    .PARAMETER Setting
        The resolved validation setting.

    .OUTPUTS
        The pending item, or $null when no worker is available (see Start-SqlDiagnosticBackground).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,

        [Parameter(Mandatory = $true)]
        $Setting
    )

    $SchemaModel = $null
    $DatabaseSchemaModel = @{}
    if ($Setting.SchemaEnabled) {
        $SchemaModel = Get-ActiveSqlSchemaModel
        $DatabaseSchemaModel = Get-CachedSqlSchemaModelByDatabase
    }

    return (Start-SqlDiagnosticBackground -TabSession $TabSession -SqlText $SqlText -Setting $Setting -SchemaModel $SchemaModel -DatabaseSchemaModel $DatabaseSchemaModel)
}

function Start-SqlDiagnosticBackground {
    <#
    .SYNOPSIS
        Runs the client-side validation passes for one tab on a worker runspace and queues the result
        for the UI thread. Returns immediately.

    .DESCRIPTION
        Issue #185. Get-SqlDiagnostic - the ScriptDom parse, the schema pass and the Omada pass - used to
        run inside the WebView2 completion poll timer's Tick, on the WPF dispatcher, after every pause
        in typing. On a real query that is hundreds of milliseconds to seconds of a frozen window,
        which is what made the editor freeze "while the autocomplete opens": both happen at the same
        idle moment.

        Here the analysis runs on a worker, and only applying the markers happens on the dispatcher.
        The pattern is the one issue #40 uses for queries: PowerShell.BeginInvoke() returns an
        IAsyncResult, which is exactly what the poll timer asks IsCompleted of, so the item goes on
        the SAME queue and is drained by the SAME timer, with the owning tab made active around its
        completion block.

        What the worker needs is resolved HERE, on the UI thread, and handed over: the setting and both
        schema models. Finding them reads application state (the active tab, the data connection
        dropdown) that only the UI thread may touch, and resolving them is cheap - the models are
        memoised. The worker therefore runs Get-SqlDiagnostic with everything bound, which is the path
        that touches nothing but the arguments.

        ONE RESULT PER TAB, AND ONLY THE LATEST. Starting a validation stops any still running for the
        same tab (Stop-SqlDiagnosticBackground), and Complete-SqlDiagnosticBackground applies a result
        only while its item is still the one registered for the tab, so markers computed for older
        text can never land on top of markers for newer text.

        The pending item deliberately has no StartedUtc. That property is what the elapsed-time
        indicator, the closed-tab clean-up and the "is a query running" check select on, and a
        validation is none of those things. It is IsBackgroundRequest, so the poll timer's own
        closed-tab check drops - and disposes - a validation whose tab has gone.

    .PARAMETER TabSession
        The tab whose editor content this is.

    .PARAMETER SqlText
        The editor content to validate.

    .PARAMETER Setting
        The resolved validation setting (Get-SqlValidationSetting).

    .PARAMETER SchemaModel
        The active data connection's indexed schema, or $null.

    .PARAMETER DatabaseSchemaModel
        lower(data connection name) -> indexed schema, for the other databases that are cached.

    .OUTPUTS
        The pending item that was queued, or $null when no worker is available - in which case the
        caller validates inline, exactly as before this existed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,

        [Parameter(Mandatory = $true)]
        $Setting,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $SchemaModel,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $DatabaseSchemaModel = @{}
    )

    # No tracer preamble: the parameters are the user's query and the tenant's schema (issue #61
    # section 5). Nothing here logs either.

    try {
        if ($null -eq $TabSession -or $null -eq $Script:PendingWebViewCompletions) {
            return $null
        }

        $Pool = Initialize-SqlDiagnosticPool
        if ($null -eq $Pool) {
            return $null
        }

        $PrivateFolder = [System.IO.Path]::Combine([string]$Script:RunTimeConfig.ModuleFolder, "Lib", "Functions", "Private")
        foreach ($WorkerFile in $Script:SqlDiagnosticWorkerFile) {
            if (-not (Test-Path -LiteralPath (Join-Path $PrivateFolder -ChildPath $WorkerFile))) {
                "Validation worker file '{0}' not found; validating on the UI thread instead." -f $WorkerFile | Write-LogOutput -LogType DEBUG
                return $null
            }
        }

        Stop-SqlDiagnosticBackground -TabSession $TabSession

        $Shell = [powershell]::Create()
        $Shell.RunspacePool = $Pool

        [void]$Shell.AddScript($Script:SqlDiagnosticWorkerScript).AddArgument($PrivateFolder).AddArgument([string[]]$Script:SqlDiagnosticWorkerFile).AddArgument($SqlText).AddArgument($Setting).AddArgument($SchemaModel).AddArgument($DatabaseSchemaModel)

        $AsyncResult = $Shell.BeginInvoke()

        $Pending = [PSCustomObject]@{
            Task                   = $AsyncResult
            Shell                  = $Shell
            TabSession             = $TabSession
            OnCompletedScriptBlock = $Script:SqlDiagnosticCompletionScript
            IsCancelled            = $false
            IsBackgroundRequest    = $true
            Description            = $Script:SqlValidationRequestDescription
        }

        $Script:SqlValidationInFlight[[string]$TabSession.Id] = $Pending

        $Script:PendingWebViewCompletions.Add($Pending)

        return $Pending
    }
    catch {
        "Validation could not be started on a worker; validating on the UI thread instead." | Write-LogOutput -LogType DEBUG
        if ($null -ne $Shell) {
            try { $Shell.Dispose() } catch { }
        }
        return $null
    }
}

function Stop-SqlDiagnosticBackground {
    <#
    .SYNOPSIS
        Abandons the validation still running for a tab, if there is one.

    .DESCRIPTION
        Called whenever that validation's answer would be about text that is no longer in the editor:
        before a newer validation is started, as soon as the user types again
        (Request-SqlSyntaxValidation), and before the execute path validates inline. The item is taken
        off the queue and its worker stopped, so its result is never applied; the identity check in
        Complete-SqlDiagnosticBackground is the second line of defence for a result that was already
        on its way.

        Cheap on purpose - it is on the per-keystroke path: one dictionary lookup when nothing is
        running, which is almost always.

    .PARAMETER TabSession
        The tab whose validation to abandon.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession
    )

    try {
        if ($null -eq $TabSession -or $null -eq $Script:SqlValidationInFlight) {
            return
        }

        $Key = [string]$TabSession.Id
        $Pending = $Script:SqlValidationInFlight[$Key]
        if ($null -eq $Pending) {
            return
        }

        $Script:SqlValidationInFlight.Remove($Key)
        $Pending.IsCancelled = $true

        if ($null -ne $Script:PendingWebViewCompletions) {
            [void]$Script:PendingWebViewCompletions.Remove($Pending)
        }

        if ($null -ne $Pending.Shell) {
            try {
                [void]$Pending.Shell.BeginStop($null, $null)
                $Pending.Shell.Dispose()
            }
            catch { }
        }
    }
    catch {
        "An earlier validation could not be stopped." | Write-LogOutput -LogType DEBUG
    }
}

function Complete-SqlDiagnosticBackground {
    <#
    .SYNOPSIS
        Collects a finished validation worker and decides whether its markers may be applied.

    .DESCRIPTION
        Runs on the UI thread, from the completion block Start-SqlDiagnosticBackground queues. Always
        disposes the worker.

        Apply is $false when the result is stale - the item was cancelled, or a newer validation for
        the same tab has been started since - and nothing is pushed: the newer one will push its own.

        A worker that FAILED is not stale. Its outcome is Apply with no diagnostics, which clears the
        markers. That is the rule the inline path has always followed (Clear-SqlEditorDiagnostic): a
        check that could not run must not leave squiggles from an earlier check of different text on
        screen, because a stale squiggle is indistinguishable from a live one.

    .PARAMETER Pending
        The pending item the poll timer hands the completion block.

    .OUTPUTS
        [PSCustomObject] with Apply ([bool]) and Diagnostic (the markers to push).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Pending
    )

    $Stale = [PSCustomObject]@{
        Apply      = $false
        Diagnostic = @()
    }

    try {
        $Key = if ($null -ne $Pending.TabSession) { [string]$Pending.TabSession.Id } else { $null }
        $Latest = $null
        if ($null -ne $Key -and $null -ne $Script:SqlValidationInFlight) {
            $Latest = $Script:SqlValidationInFlight[$Key]
        }

        if ($Pending.IsCancelled -or -not [object]::ReferenceEquals($Latest, $Pending)) {
            return $Stale
        }

        $Script:SqlValidationInFlight.Remove($Key)

        $Output = $null
        try {
            $Output = @($Pending.Shell.EndInvoke($Pending.Task)) | Select-Object -Last 1
        }
        catch {
            "The validation worker failed; clearing the editor diagnostics." | Write-LogOutput -LogType DEBUG
            return [PSCustomObject]@{
                Apply      = $true
                Diagnostic = @()
            }
        }

        if ($null -eq $Output -or $null -eq $Output.Result -or $Output.Result.Status -ne "Ok") {
            return [PSCustomObject]@{
                Apply      = $true
                Diagnostic = @()
            }
        }

        # Counts and timing only (issue #61 section 5): this is what makes a slow validation visible in
        # the log without putting the query in it.
        "Validated the editor content on a worker in {0} ms: {1} diagnostic(s)." -f $Output.ElapsedMilliseconds, @($Output.Result.Diagnostic).Count | Write-LogOutput -LogType DEBUG

        return [PSCustomObject]@{
            Apply      = $true
            Diagnostic = @($Output.Result.Diagnostic)
        }
    }
    catch {
        "Collecting the validation result failed." | Write-LogOutput -LogType DEBUG
        return $Stale
    }
    finally {
        if ($null -ne $Pending.Shell) {
            try { $Pending.Shell.Dispose() } catch { }
        }
    }
}

function Initialize-SqlDiagnosticPool {
    <#
    .SYNOPSIS
        Returns the runspace pool validation workers run in, opening it in the background on first use.

    .DESCRIPTION
        A pool of its own rather than a slot in the Omada request pool (Initialize-OmadaRequestPool).
        That pool imports OmadaWeb.PS into every worker, which validation does not need, and sharing it
        would let a burst of validations queue in front of a query the user is waiting for.

        One worker. Validations of one tab supersede each other, so more than one running at a time is
        only ever useful across tabs, and the user types in one tab at a time.

        Opened with BeginOpen, never Open: opening a runspace costs a few hundred milliseconds, and
        paying that on the UI thread is exactly what this issue removes. Until the pool is open this
        returns $null and the caller validates inline - the first validation of a session costs what
        every validation used to.

        A pool that has broken or closed is thrown away and reopened on the next call.

    .OUTPUTS
        The open RunspacePool, or $null while it is opening or when it could not be created.
    #>
    [CmdletBinding()]
    param()

    try {
        $Pool = $Script:SqlDiagnosticPool
        if ($null -ne $Pool) {
            $State = $Pool.RunspacePoolStateInfo.State
            if ($State -eq [System.Management.Automation.Runspaces.RunspacePoolState]::Opened) {
                return $Pool
            }
            if ($State -in @([System.Management.Automation.Runspaces.RunspacePoolState]::BeforeOpen, [System.Management.Automation.Runspaces.RunspacePoolState]::Opening)) {
                return $null
            }

            try { $Pool.Dispose() } catch { }
            $Script:SqlDiagnosticPool = $null
        }

        $SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $SessionState.ApartmentState = [System.Threading.ApartmentState]::MTA

        $Pool = [runspacefactory]::CreateRunspacePool(1, 1, $SessionState, $Host)
        $Pool.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        [void]$Pool.BeginOpen($null, $null)

        $Script:SqlDiagnosticPool = $Pool
        "Opening the validation worker in the background." | Write-LogOutput -LogType DEBUG
        return $null
    }
    catch {
        "Could not open the validation worker; validation runs on the UI thread." | Write-LogOutput -LogType DEBUG
        $Script:SqlDiagnosticPool = $null
        return $null
    }
}

function Close-SqlDiagnosticPool {
    <#
    .SYNOPSIS
        Closes the validation worker pool, if one was opened.

    .DESCRIPTION
        Worker threads keep the process alive after the window has gone (issue #40), so this is called
        from the main window's Closing handler next to Close-OmadaRequestPool. Best-effort.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $Script:SqlDiagnosticPool) {
        return
    }

    try { $Script:SqlDiagnosticPool.Close() } catch { }
    try { $Script:SqlDiagnosticPool.Dispose() } catch { }
    $Script:SqlDiagnosticPool = $null
    $Script:SqlValidationInFlight = @{}
}
