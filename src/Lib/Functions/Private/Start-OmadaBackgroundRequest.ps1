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

        [string]$Description = "Omada request"
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Description: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, $Description))

        $Private:Pool = Initialize-OmadaRequestPool
        if ($null -eq $Private:Pool) {
            return $null
        }

        $Private:CorePath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Lib\Functions\Private\Invoke-OmadaRequestCore.ps1"
        if (-not (Test-Path -LiteralPath $Private:CorePath)) {
            "Background request core not found at '{0}'; running on the UI thread instead." -f $Private:CorePath | Write-LogOutput -LogType WARNING -SkipDialog
            return $null
        }

        $Private:Shell = [powershell]::Create()
        $Private:Shell.RunspacePool = $Private:Pool

        # The worker dot-sources the core from disk rather than being handed its source text: one
        # copy of the function, and the file is already the thing the unit tests execute.
        # $TransportScriptPath is the test seam - see Start-OmadaBackgroundRequest's note below.
        [void]$Private:Shell.AddScript({
                param($CorePath, $RequestParameters, $TransportScriptPath, $TransportContext)
                . $CorePath
                if (![string]::IsNullOrWhiteSpace($TransportScriptPath) -and (Test-Path -LiteralPath $TransportScriptPath)) {
                    . $TransportScriptPath
                    $Initializer = Get-Command -Name Initialize-OmadaRequestWorkerTransport -ErrorAction SilentlyContinue
                    if ($null -ne $Initializer) {
                        Initialize-OmadaRequestWorkerTransport -Context $TransportContext
                    }
                }
                return (Invoke-OmadaRequestCore -Parameters $RequestParameters)
            }).AddArgument($Private:CorePath).AddArgument($Parameters.Clone()).AddArgument($Script:OmadaRequestWorkerTransportPath).AddArgument($Script:OmadaRequestWorkerTransportContext)

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
        }

        # Deliberately NOT assigned to $Script:Task or $TabSession.PendingTask. That field belongs
        # exclusively to the WebView2 editor task: Set-ActiveTabContext saves and restores it per
        # tab, and half a dozen call sites read $Script:Task.Status expecting "RanToCompletion".
        # An IAsyncResult has no Status property, so parking one there would silently turn every one
        # of those reads into $null. Background requests live in the queue and nowhere else.
        $Script:PendingWebViewCompletions.Add($Private:Pending)

        "Dispatched background request: {0}" -f $Description | Write-LogOutput -LogType DEBUG
        return $Private:Pending
    }
    catch {
        "Could not dispatch a background request ({0}); it will run on the UI thread. {1}" -f $Description, $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        return $null
    }
}
