function Start-OmadaBackgroundRequest {
    <#
    .SYNOPSIS
    Issue an Omada request on a background worker and enqueue its completion onto the existing
    WebView2 completion queue. Returns immediately.

    .DESCRIPTION
    Issue #40. The design insight that makes this cheap: the poll timer in MainForm.Definition.ps1
    only ever asks $_.Task.IsCompleted, and PowerShell.BeginInvoke() returns an IAsyncResult, which
    exposes exactly that property. So a background request can be queued into the SAME
    $Script:PendingWebViewCompletions list, drained by the SAME 50 ms timer, invoking its completion
    block from the SAME call frame that already repoints the owning tab via Set-ActiveTabContext -
    with no change to the Tick handler at all. One completion queue, not two.

    The completion block is invoked with the whole pending item as its argument, so it reads
    $Pending.Shell and calls Complete-OmadaBackgroundRequest to collect the outcome. It must be a
    PLAIN scriptblock, never a .GetNewClosure() block, for the reason documented at the top of
    MainForm.Definition.ps1: a closure runs in a detached dynamic module that cannot resolve this
    module's private functions.

    .PARAMETER Parameters
    The prepared Invoke-OmadaRestMethod splat. CLONED here before it crosses the runspace boundary:
    $Script:RunTimeData.RestMethodParam is long-lived, is mutated by the next call site, and
    Set-ActiveTabContext can swap the whole RunTimeData object out from under a request that is
    still in flight. A worker reading the live hashtable would see whichever request came after it.

    .PARAMETER TabSession
    The tab this request belongs to. The poll timer repoints to it before invoking the completion
    block and restores the previously active tab afterwards.

    .PARAMETER OnCompletedScriptBlock
    Plain scriptblock invoked on the UI thread with the pending item as its argument.

    .PARAMETER Context
    Arbitrary caller data, attached to the pending item as .Context and therefore reachable from the
    completion block. This is how a plain scriptblock gets its inputs: a plain block resolves
    variables from the scope it is INVOKED in - the poll timer's frame - not the one it was written
    in, so anything the completion needs must travel on the item. It is also how a completion avoids
    re-reading $Script: state that another tab may have repointed in the meantime.

    .PARAMETER Description
    Short label for the log and for the elapsed-time indicator.

    .OUTPUTS
    The pending item that was enqueued, or $null when the request could not be dispatched (in which
    case the caller must run it synchronously).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $true)]
        $TabSession,

        [Parameter(Mandatory = $true)]
        [scriptblock]$OnCompletedScriptBlock,

        $Context,

        # When supplied, the worker runs the whole dependent execute chain (Invoke-OmadaExecutePipeline)
        # instead of a single request, and returns its outcome as the Result. This is what makes C1-5
        # possible with ONE completion rather than five - see the pipeline's own notes.
        [hashtable]$PipelineContext,

        [string]$Description = "Omada request"
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Description: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, $Description))

        $Private:Pool = Initialize-OmadaRequestPool
        if ($null -eq $Private:Pool) {
            return $null
        }

        # Everything the worker will dot-source is checked here, not just the core: a missing file
        # must mean "fall back to the UI thread", the way every other unavailability does. Checking
        # only the core would dispatch a worker that then fails on its first line - turning a clean
        # fallback into a failed request.
        $Private:PrivateFolder = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Lib\Functions\Private"
        $Private:RequiredWorkerFiles = @("Invoke-OmadaRequestCore.ps1")
        if ($null -ne $PipelineContext) {
            $Private:RequiredWorkerFiles += @("New-OmadaQueryRequest.ps1", "Invoke-OmadaExecutePipeline.ps1")
        }
        foreach ($Private:WorkerFile in $Private:RequiredWorkerFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $Private:PrivateFolder -ChildPath $Private:WorkerFile))) {
                "Background worker file '{0}' not found under '{1}'; running on the UI thread instead." -f $Private:WorkerFile, $Private:PrivateFolder | Write-LogOutput -LogType WARNING -SkipDialog
                return $null
            }
        }

        # The pipeline builds each step's request itself, but every step still goes out with the
        # session's own transport settings - SessionKey, authentication, redaction - so it is handed
        # the same prepared splat a single request would have used. Cloned, and into a clone of the
        # context, for the reason the -Parameters help gives: the live hashtable is mutated by the
        # next call site.
        # A synchronized table the worker can publish into while it is still running. Only used by
        # the pipeline, and only for the temporary object's id: cancellation kills the worker outright
        # so its own clean-up never runs, and the UI has to know which object to remove.
        $Private:Progress = [hashtable]::Synchronized(@{})
        if ($null -ne $PipelineContext) {
            $PipelineContext = $PipelineContext.Clone()
            $PipelineContext.Parameters = $Parameters.Clone()
            $PipelineContext.Progress = $Private:Progress
        }

        $Private:Shell = [powershell]::Create()
        $Private:Shell.RunspacePool = $Private:Pool

        # The worker dot-sources what it needs from disk rather than being handed source text: one
        # copy of every function, and those files are already the things the unit tests execute.
        # $TransportScriptPath is the mock seam - see Install-OmadaMockTransport.
        [void]$Private:Shell.AddScript({
                param($PrivateFolder, $RequestParameters, $PipelineContext, $TransportScriptPath, $TransportContext)
                . (Join-Path $PrivateFolder "Invoke-OmadaRequestCore.ps1")
                if ($null -ne $PipelineContext) {
                    . (Join-Path $PrivateFolder "New-OmadaQueryRequest.ps1")
                    . (Join-Path $PrivateFolder "Invoke-OmadaExecutePipeline.ps1")
                }
                if (![string]::IsNullOrWhiteSpace($TransportScriptPath) -and (Test-Path -LiteralPath $TransportScriptPath)) {
                    . $TransportScriptPath
                    $Initializer = Get-Command -Name Initialize-OmadaRequestWorkerTransport -ErrorAction SilentlyContinue
                    if ($null -ne $Initializer) {
                        Initialize-OmadaRequestWorkerTransport -Context $TransportContext
                    }
                }
                if ($null -ne $PipelineContext) {
                    $PipelineOutcome = Invoke-OmadaExecutePipeline -Context $PipelineContext
                    # Reported in the transport's own shape so the UI-side plumbing needs no special
                    # case: the whole outcome is the Result, and the pipeline's first failure is also
                    # surfaced as the ErrorRecord so Resolve-OmadaRequestFailure still classifies an
                    # Unauthorized or a missing OData endpoint exactly as it does for a single request.
                    return @{ Result = $PipelineOutcome; ErrorRecord = $PipelineOutcome.ErrorRecord }
                }
                return (Invoke-OmadaRequestCore -Parameters $RequestParameters)
            }).AddArgument($Private:PrivateFolder).AddArgument($Parameters.Clone()).AddArgument($PipelineContext).AddArgument($Script:OmadaRequestWorkerTransportPath).AddArgument($Script:OmadaRequestWorkerTransportContext)

        $Private:AsyncResult = $Private:Shell.BeginInvoke()

        $Private:Pending = [PSCustomObject]@{
            # Named Task, and polled through IsCompleted, so the existing Tick handler needs no
            # change. This is an IAsyncResult, NOT a WebView2 Task - see IsBackgroundRequest.
            Task                   = $Private:AsyncResult
            Shell                  = $Private:Shell
            TabSession             = $TabSession
            OnCompletedScriptBlock = $OnCompletedScriptBlock
            StartedUtc             = [DateTime]::UtcNow
            IsCancelled            = $false
            IsBackgroundRequest    = $true
            Description            = $Description
            Context                = $Context
            Progress               = $Private:Progress
        }

        # Deliberately NOT assigned to $Script:Task or $TabSession.PendingTask. That field belongs
        # exclusively to the WebView2 editor task: Set-ActiveTabContext saves and restores it per
        # tab, and half a dozen call sites read $Script:Task.Status expecting "RanToCompletion".
        # An IAsyncResult has no Status property, so parking one there would silently turn every one
        # of those reads into $null. Background requests live in the queue and nowhere else.
        $Script:PendingWebViewCompletions.Add($Private:Pending)

        "Dispatched background request: {0}" -f $Description | Write-LogOutput -LogType DEBUG
        # Handed over: from here the completion owns the shell and will dispose it. Nulling the local
        # is what tells the catch below not to dispose a shell that is now in flight.
        $Private:Shell = $null
        return $Private:Pending
    }
    catch {
        # Dispose a half-created worker. AddScript, BeginInvoke or the queue Add can throw after the
        # [powershell] exists, and the caller then falls back to a synchronous request - so nothing
        # else will ever reach this shell to release its runspace back to the pool. Leaking one per
        # failure would eventually starve the pool of the very workers the fallback exists to
        # compensate for.
        if ($null -ne $Private:Shell) {
            try { $Private:Shell.Dispose() } catch { }
        }
        "Could not dispatch a background request ({0}); it will run on the UI thread. {1}" -f $Description, $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        return $null
    }
}
