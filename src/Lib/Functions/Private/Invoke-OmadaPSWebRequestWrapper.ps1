function Invoke-OmadaPSWebRequestWrapper {
    [CmdLetBinding()]
    param()

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

    # Invoke-OmadaRestMethod (OmadaWeb.PS) can show its own interactive WebView2/Browser login
    # popup when authentication is needed - a modal window this app does not own, but which pumps
    # this thread's messages while blocked exactly like our own dialogs (see
    # Suspend-WebViewCompletionPolling.ps1). Without suspending, the WebViewCompletionPollTimer can
    # fire reentrantly during that popup and process a DIFFERENT tab's WebView2 completion,
    # repointing $Script:MainForm.Elements/$Script:AppConfig/etc. mid-call.
    #
    # Issue #40's last criterion asks for this suppression to be "simplified or removed where it is
    # no longer needed". Removing it from here would be exactly backwards, and it is worth writing
    # down why, because the plan for that slice assumed the opposite.
    #
    # Before #40 this was the single choke point every Omada request went through, so it covered all
    # of them - most of which could never have opened a dialog. Now the requests that cannot open a
    # dialog do not come through here at all: they go to a worker, and
    # Invoke-OmadaPSWebRequestWrapperAsync suspends nothing, because there is nothing on the UI
    # thread to protect. What is left calling this function is precisely the set of cases
    # Test-OmadaBackgroundRequestEligible refuses to dispatch - a tab that has not authenticated, or
    # a request that explicitly asks to authenticate again - which is to say: the login prompt now
    # happens HERE, by design, and nowhere else. The suppression is more necessary than it was, not
    # less.
    #
    # The simplification that IS available is narrowing it. It used to be held across parameter
    # preparation, two rounds of redaction and logging, and the whole error classification - during
    # all of which no dialog can appear, and every completion in the queue was needlessly delayed.
    # It now covers just the call that can actually show a window. (Write-LogOutput and
    # Set-SqlConnectionState open their own dialogs on some paths and suspend for themselves; the
    # helper is idempotent, so a nested suspend is harmless either way.)
    try {
        if (!$Script:RunTimeData.SkipRetryRequest) {
            # Preparation and failure classification live in Build-OmadaRequestParameter and
            # Resolve-OmadaRequestFailure so the background path (issue #40,
            # Invoke-OmadaPSWebRequestWrapperAsync) applies exactly the same rules. This function is
            # still the synchronous choke point, and is still what runs when a request is not
            # eligible for a worker or no worker could be had.
            $Private:Parameters = Build-OmadaRequestParameter

            "Parameters: {0}" -f (ConvertTo-RedactedLogString -InputObject $Private:Parameters) | Write-LogOutput -LogType VERBOSE

            # The call itself lives in Invoke-OmadaRequestCore, which reads no $Script: state and
            # writes no log - the one part of this function that can legally run in a worker runspace.
            # The core returns the failure instead of throwing it, so this rethrows to keep the
            # control flow identical: a rethrown ErrorRecord keeps its Exception, ErrorDetails and
            # FullyQualifiedErrorId, which is all the classification reads.
            Suspend-WebViewCompletionPolling
            try {
                $Private:Outcome = Invoke-OmadaRequestCore -Parameters $Private:Parameters
            }
            finally {
                Resume-WebViewCompletionPolling
            }

            if ($null -ne $Private:Outcome.ErrorRecord) {
                throw $Private:Outcome.ErrorRecord
            }
            $Private:Result = $Private:Outcome.Result

            # Deliberately no status-bar write here. A successful request is not the same thing as a
            # connected tab: this transport is also used by probes and by work that runs while a tab
            # is being connected, so writing "Connected" from here put the status bar ahead of - and
            # sometimes in contradiction with - the rest of the UI, which is all derived from
            # $Script:ConnectionStatus (Test-ConnectionButton for the button text,
            # Set-SqlQueryFunctionState for the dropdowns and Display name). Connection state is
            # single-sourced: Set-SqlConnectionState is the only writer of both the flag and the
            # status bar text.
            "Result: {0}" -f (ConvertTo-RedactedLogString -InputObject $Private:Result) | Write-LogOutput -LogType VERBOSE
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            return $Private:Result
        }
        else {
            return $null
        }
    }
    catch {
        Resolve-OmadaRequestFailure -ErrorRecord $_
    }
}
