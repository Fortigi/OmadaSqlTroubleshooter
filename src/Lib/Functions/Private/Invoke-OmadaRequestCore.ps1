function Invoke-OmadaRequestCore {
    <#
    .SYNOPSIS
    The one statement that actually talks to Omada: splat a plain parameter hashtable into
    OmadaWeb.PS's Invoke-OmadaRestMethod and hand back the result or the error, never throwing.

    .DESCRIPTION
    This function is deliberately, strictly dependency-free. It reads no $Script: state, writes no
    log, touches no WPF element and suspends no timer. Everything it needs arrives in $Parameters and
    everything it produces leaves in the returned hashtable.

    That is not stylistic. A PowerShell runspace has entirely separate session state: a worker
    runspace has no $Script:RunTimeData, no $Script:AppConfig, no $Script:MainForm and no
    $Script:Tracer, and any call to a private function of this module - Write-LogOutput included -
    is a CommandNotFoundException there. Issue #40 moves the network call off the WPF UI thread, so
    the seam between "runs anywhere" and "runs only on the UI thread" has to be drawn somewhere, and
    this is it. Invoke-OmadaPSWebRequestWrapper cannot be that seam: it reads
    $Script:RunTimeData.RestMethodParam, $Script:RunTimeConfig, $Script:AppConfig.BaseUrl, and calls
    Set-SqlConnectionState, Write-LogOutput and Suspend/Resume-WebViewCompletionPolling. All of that
    stays on the UI thread, above this call.

    Errors are RETURNED rather than thrown. A pipeline running in a worker runspace has no useful
    place to throw to, and the caller has to be able to inspect the failure on the UI thread where
    the app's error classification, connection-state teardown and dialogs actually work. The
    ErrorRecord that comes back carries its original Exception, ErrorDetails and
    FullyQualifiedErrorId, which is everything the callers classify on.

    .PARAMETER Parameters
    The complete, already-prepared splat for Invoke-OmadaRestMethod. Callers dispatching this to a
    worker must pass a CLONE, not the live $Script:RunTimeData.RestMethodParam: that hashtable is
    long-lived, is mutated by the next call site, and Set-ActiveTabContext can swap the whole
    RunTimeData object out from under a request that is still in flight.

    .OUTPUTS
    Hashtable @{ Result = <response or $null>; ErrorRecord = <ErrorRecord or $null> }.

    ErrorRecord is the discriminator, and it is the only one: a non-null ErrorRecord means the request
    failed and Result is $null. A null ErrorRecord means the request succeeded - but Result may still
    be $null, because a successful Omada call can legitimately return nothing. Callers must therefore
    branch on ErrorRecord and never infer failure from a null Result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    try {
        return @{
            Result      = (Invoke-OmadaRestMethod @Parameters)
            ErrorRecord = $null
        }
    }
    catch {
        return @{
            Result      = $null
            ErrorRecord = $_
        }
    }
}
