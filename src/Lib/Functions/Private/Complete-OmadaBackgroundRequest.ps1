function Complete-OmadaBackgroundRequest {
    <#
    .SYNOPSIS
    Collect the outcome of a background request on the UI thread and release its worker.

    .DESCRIPTION
    Called from a completion block that the poll timer invoked, so this runs on the UI thread inside
    a frame where this module's private functions resolve and the owning tab has already been made
    active by Set-ActiveTabContext. That is the whole point of routing background work through the
    existing completion queue: everything that needs the app's state runs here, not in the worker.

    Returns the same @{ Result; ErrorRecord } shape as Invoke-OmadaRequestCore, so a caller handles a
    background failure exactly as it handles a synchronous one. ErrorRecord is the discriminator; a
    null Result on its own does not mean failure.

    .NOTES
    EndInvoke on a pipeline that was stopped THROWS - verified, not assumed - so the cancelled case
    is checked before EndInvoke is called rather than being caught afterwards. A cancelled request
    reports neither a result nor an error: nothing failed, the caller simply stopped waiting.

    The [powershell] is always disposed. For a cancelled request that matters more than tidiness: a
    pipeline killed mid-request leaves a half-read HTTP stream and a WebRequestSession in an unknown
    state, so its runspace must be discarded rather than handed back to the pool for the next query.
    Disposing the shell is what releases it.

    .PARAMETER Pending
    The queue item created by Start-OmadaBackgroundRequest.

    .OUTPUTS
    Hashtable @{ Result; ErrorRecord; IsCancelled }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Pending
    )

    $Private:Outcome = @{
        Result      = $null
        ErrorRecord = $null
        IsCancelled = [bool]$Pending.IsCancelled
    }

    try {
        if ($Pending.IsCancelled) {
            return $Private:Outcome
        }

        $Private:Output = $Pending.Shell.EndInvoke($Pending.Task)

        # AddScript returns the core's hashtable through the pipeline, so it arrives wrapped in the
        # output collection. Take the first entry that looks like the contract rather than assuming
        # a position: a worker that also wrote to the output stream would otherwise shift it.
        $Private:Core = @($Private:Output) | Where-Object { $_ -is [hashtable] -and $_.ContainsKey("ErrorRecord") } | Select-Object -First 1

        if ($null -eq $Private:Core) {
            # The worker returned something this function does not understand. Surface the worker's
            # own error stream if it has one, so the cause is not swallowed.
            $Private:WorkerError = @($Pending.Shell.Streams.Error) | Select-Object -First 1
            if ($null -ne $Private:WorkerError) {
                $Private:Outcome.ErrorRecord = $Private:WorkerError
            }
            return $Private:Outcome
        }

        $Private:Outcome.Result = $Private:Core.Result
        $Private:Outcome.ErrorRecord = $Private:Core.ErrorRecord
        return $Private:Outcome
    }
    catch {
        $Private:Outcome.ErrorRecord = $_
        return $Private:Outcome
    }
    finally {
        try { $Pending.Shell.Dispose() } catch { }
    }
}
