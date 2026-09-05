function Resolve-ExecuteFallbackAction {
    <#
    .SYNOPSIS
    Decide what a failed background execute means: re-run it on the UI thread, stop using background
    workers altogether, or simply report what the tenant said.

    .DESCRIPTION
    This exists because the first version of the fallback got the distinction wrong, with real
    consequences. It treated "the pipeline failed before completing a step" as "the worker cannot run
    requests", so a single HTTP 502 from the tenant permanently disabled background execution for the
    rest of the session - the window stopped staying responsive for the rest of the day because of one
    transient blip at the far end.

    A Bad Gateway says nothing about the worker. If an HTTP status came back at all, the worker
    reached the tenant, which is proof it works. The three outcomes are therefore:

      Report            The tenant answered, with something other than 401. Re-running on the UI
                        thread would send the identical request and get the identical answer, so the
                        only useful thing to do is tell the user what happened.

      Retry             Worth one attempt on the UI thread, but the worker is not written off. A 401
                        is the case that matters: the session has expired and a worker cannot sign in,
                        but the UI thread can - and once it has, the worker may well work again.

      RetryAndDisable   The worker produced nothing at all, or failed in a way that means it can never
                        run a request in this session - no WebView2 runtime, an interactive sign-in
                        attempted where no window can exist. Retry on the UI thread and stop
                        dispatching to workers.

    Deliberately conservative: an unrecognised failure is Retry, never RetryAndDisable. Disabling is
    a one-way door for the session, so it is taken only on evidence, not on the absence of it.

    .PARAMETER Outcome
    The pipeline outcome from Invoke-OmadaExecutePipeline, or $null when the worker returned nothing.

    .OUTPUTS
    [string] one of "Report", "Retry", "RetryAndDisable".
    #>
    [CmdLetBinding()]
    [OutputType([string])]
    param(
        $Outcome
    )

    # Nothing came back: the worker died, could not load its module, or never ran. There is no
    # evidence it can serve anything, and the query still has to happen.
    if ($null -eq $Outcome -or $null -eq $Outcome.ErrorRecord) {
        return "RetryAndDisable"
    }

    # Any completed step is proof the worker can reach the tenant. Whatever failed afterwards is the
    # tenant's answer, and re-running it would repeat work the tenant has already done - including,
    # potentially, executing the query a second time.
    if ([int]$Outcome.CompletedSteps -gt 0) {
        return "Report"
    }

    $Private:StatusCode = Get-OmadaHttpStatusCode -ErrorRecord $Outcome.ErrorRecord
    if ($null -ne $Private:StatusCode) {
        # A status code means a round trip completed. The worker is fine.
        if ($Private:StatusCode -eq 401) {
            return "Retry"
        }

        return "Report"
    }

    # No status code. Look for the failures that mean this worker can never run a request: they all
    # come from a worker being pushed into an interactive sign-in it cannot perform. Matched on text
    # because the exception arrives flattened across the runspace boundary.
    $Private:Message = [string]$Outcome.ErrorRecord.Exception.Message
    $Private:WorkerFailurePattern = @(
        "WebView2RuntimeNotFoundException"
        "Couldn't find a compatible Webview2 Runtime"
        "Error creating CoreWebView2Environment"
        "Start-WebView2Login"
        "Login try count exceeded"
    )

    foreach ($Private:Pattern in $Private:WorkerFailurePattern) {
        if ($Private:Message -like ("*{0}*" -f $Private:Pattern)) {
            return "RetryAndDisable"
        }
    }

    return "Retry"
}
