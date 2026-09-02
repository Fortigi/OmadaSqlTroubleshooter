function Invoke-OmadaPSWebRequestWrapper {
    [CmdLetBinding()]
    param()

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

    # Invoke-OmadaRestMethod (OmadaWeb.PS) can show its own interactive WebView2/Browser login
    # popup when authentication is needed - a modal window this app does not own, but which pumps
    # this thread's messages while blocked exactly like our own dialogs (see
    # Suspend-WebViewCompletionPolling.ps1). Without suspending here, the WebViewCompletionPollTimer
    # can fire reentrantly during that popup and process a DIFFERENT tab's WebView2 completion,
    # repointing $Script:MainForm.Elements/$Script:AppConfig/etc. mid-call - corrupting which tab's
    # UI this function's own status updates (and any Set-SqlConnectionState a caller makes right
    # after it returns) end up applying to. This is the single choke point every Omada REST call in
    # this app goes through, so suspending here covers all of them.
    Suspend-WebViewCompletionPolling
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
            $Private:Outcome = Invoke-OmadaRequestCore -Parameters $Private:Parameters
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
    finally {
        Resume-WebViewCompletionPolling
    }
}
