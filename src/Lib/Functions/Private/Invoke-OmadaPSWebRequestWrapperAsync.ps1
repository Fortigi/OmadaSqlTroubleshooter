function Invoke-OmadaPSWebRequestWrapperAsync {
    <#
    .SYNOPSIS
    Background sibling of Invoke-OmadaPSWebRequestWrapper: prepare the request on the UI thread,
    issue it on a worker, and return immediately. Returns $null when the request must run inline.

    .DESCRIPTION
    Issue #40. The contract deliberately makes the fallback the caller's business rather than hiding
    it: this returns $null - having done nothing - whenever the request may not, or cannot, go to a
    worker, and the caller then does exactly what it did before by calling
    Invoke-OmadaPSWebRequestWrapper. There are three such cases:

      - $Script:RunTimeData.SkipRetryRequest is set. The synchronous wrapper answers $null for this
        without making a request, and that decision must not be duplicated here.
      - Test-OmadaBackgroundRequestEligible says no - the tab is not authenticated, or the request
        asks to re-authenticate. Interactive authentication belongs on the UI thread.
      - No pool could be opened, or dispatch failed. Slower is better than broken.

    On completion, $OnResultScriptBlock is invoked on the UI thread by the completion poll timer,
    with the pending item as its argument, after the owning tab has been made active. It receives
    the response through $Pending.Outcome, whose shape matches what the synchronous wrapper returns:
    the response object on success, an ErrorRecord for an unclassified failure. The two classified
    failures (OData endpoint missing, Unauthorized) are handled here by Resolve-OmadaRequestFailure,
    which throws - so a caller sees precisely what it would have seen inline.

    .PARAMETER OnResultScriptBlock
    A PLAIN scriptblock (never .GetNewClosure() - see MainForm.Definition.ps1) invoked on the UI
    thread. Reads its data from the pending item passed as its argument: $Pending.Outcome for the
    response, $Pending.Context for whatever the caller attached.

    .PARAMETER Context
    Caller data carried to the completion block, where it is read as $Pending.Context.Caller.
    Anything the completion needs that would otherwise have to be re-read from $Script: state
    belongs here: by the time the block runs, other work may have moved the active tab, and
    re-reading is how a completion ends up acting on the wrong tab.

    .PARAMETER Description
    Short label for logging and the elapsed-time indicator.

    .OUTPUTS
    The pending queue item, or $null when the caller must run the request synchronously.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$OnResultScriptBlock,

        $Context,

        # When supplied, the worker runs the whole dependent execute chain rather than a single
        # request (issue #40, C1-5). $Pending.Outcome is then the pipeline's outcome object instead
        # of a single response - or an ErrorRecord, when the failure was one of the two tenant-level
        # kinds Resolve-OmadaRequestFailure classifies.
        [hashtable]$PipelineContext,

        [string]$Description = "Omada request"
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Description: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, $Description))

        if ($Script:RunTimeData.SkipRetryRequest) {
            return $null
        }

        $Private:Parameters = Build-OmadaRequestParameter

        if (-not (Test-OmadaBackgroundRequestEligible -Parameters $Private:Parameters)) {
            "Request '{0}' is not eligible for a background worker; running on the UI thread." -f $Description | Write-LogOutput -LogType DEBUG
            return $null
        }

        "Parameters: {0}" -f (ConvertTo-RedactedLogString -InputObject $Private:Parameters) | Write-LogOutput -LogType VERBOSE

        $Private:TabSession = Get-ActiveTabSession
        if ($null -eq $Private:TabSession) {
            return $null
        }

        # Both the caller's data and the caller's result block travel on .Context, and are assembled
        # BEFORE dispatch. Attaching the result block to the item after Start-OmadaBackgroundRequest
        # returned would work today - nothing pumps the dispatcher in between, so the poll timer
        # cannot fire - but it would be correct only by that accident, and this queue is about to be
        # drained by more code than it is now.
        $Private:RequestContext = @{
            Caller   = $Context
            OnResult = $OnResultScriptBlock
        }

        # The completion block below is the bridge back onto the UI thread. It is a plain block: it
        # reads everything it needs from $Pending, and calls only module-private functions, which
        # resolve because the poll timer invokes it from a top-level frame.
        return Start-OmadaBackgroundRequest -Parameters $Private:Parameters -TabSession $Private:TabSession -Description $Description -Context $Private:RequestContext -PipelineContext $PipelineContext -OnCompletedScriptBlock {
            param($Pending)

            $Private:Outcome = Complete-OmadaBackgroundRequest -Pending $Pending

            if ($Private:Outcome.IsCancelled) {
                "Background request cancelled: {0}" -f $Pending.Description | Write-LogOutput -LogType DEBUG
                return
            }

            try {
                if ($null -ne $Private:Outcome.ErrorRecord) {
                    # Same classification as the inline path. The two tenant-level branches throw,
                    # which the poll timer catches and logs; the third returns the ErrorRecord, which
                    # is what callers test with -is [ErrorRecord].
                    $Pending | Add-Member -NotePropertyName "Outcome" -NotePropertyValue (Resolve-OmadaRequestFailure -ErrorRecord $Private:Outcome.ErrorRecord) -Force
                }
                else {
                    "Result: {0}" -f (ConvertTo-RedactedLogString -InputObject $Private:Outcome.Result) | Write-LogOutput -LogType VERBOSE
                    $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
                    $Pending | Add-Member -NotePropertyName "Outcome" -NotePropertyValue $Private:Outcome.Result -Force
                }
            }
            finally {
                # In a finally, and this is not defensive tidiness. Resolve-OmadaRequestFailure THROWS
                # for the two tenant-level failures (Unauthorized, OData endpoint missing). Without
                # this the caller's result block would be skipped for exactly those cases - and for an
                # execute that block is what closes the "Executing Query..." popup, re-enables the
                # buttons and stops the stopwatch. The item has already been removed from the queue by
                # the poll timer, so nothing else would ever run it: the tab would simply stay stuck
                # mid-execute after an expired session, which is the worst possible moment for it.
                #
                # The throw still propagates afterwards, so the "tenant-level failures throw"
                # contract is unchanged; the poll timer catches and logs it as before.
                if ($null -eq $Pending.Outcome) {
                    $Pending | Add-Member -NotePropertyName "Outcome" -NotePropertyValue $Private:Outcome.ErrorRecord -Force
                }
                & $Pending.Context.OnResult $Pending
            }
        }
    }
    catch {
        "Could not start a background request ({0}); it will run on the UI thread. {1}" -f $Description, $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        return $null
    }
}
