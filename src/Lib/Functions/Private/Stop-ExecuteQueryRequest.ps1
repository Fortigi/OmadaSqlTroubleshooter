function Stop-ExecuteQueryRequest {
    <#
    .SYNOPSIS
    Abandon the wait for the active tab's in-flight query and return the tab to a clean state.

    .DESCRIPTION
    Issue #40's Cancel button. What it does, precisely, and the wording matters because the UI says
    the same thing:

      - It stops THIS APPLICATION waiting. The query goes on executing on the Omada server. There is
        no server-side cancellation to call - that is issue #43 - so claiming otherwise would be a
        lie the user could act on (starting a "replacement" query while the first still holds the
        same server resources).
      - The temporary TMP_<guid> object created for an "execute selection" run is still deleted.
        Cancelling between creating it and the completion that would have removed it is exactly how
        one gets left behind on the tenant. New-TemporarySqlQueryObject reuses and undeletes a stale
        one on the next run, so the damage self-heals - but leaving litter on someone's tenant
        because they clicked Cancel is not acceptable.
      - The results grid is left alone. Abandoning a query must not blank a perfectly good previous
        result.

    .NOTES
    The stopped runspace is discarded, not returned to the pool. A pipeline killed mid-request leaves
    a half-read HTTP stream and a WebRequestSession in an unknown state, so the [powershell] is
    disposed and the pool creates a replacement.

    Removing the item from the queue here - rather than letting the poll timer drain it - is what
    makes the cancellation immediate from the UI's point of view: Get-ActiveExecuteQueryRequest stops
    reporting the tab as executing, so the button flips back to Execute in the same click.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        $Private:Pending = Get-ActiveExecuteQueryRequest
        if ($null -eq $Private:Pending) {
            "No query is running on this tab; nothing to cancel." | Write-LogOutput -LogType DEBUG
            return
        }

        # Marked and de-queued before anything that can block, so nothing else treats this tab as
        # still executing while the clean-up below runs.
        $Private:Pending.IsCancelled = $true
        [void]$Script:PendingWebViewCompletions.Remove($Private:Pending)

        try {
            if ($null -ne $Private:Pending.Shell) {
                [void]$Private:Pending.Shell.BeginStop($null, $null)
                $Private:Pending.Shell.Dispose()
            }
        }
        catch {
            # A worker that had already finished throws here; the item is off the queue either way.
            "Stopping the query worker reported: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
        }

        # Read from the worker's progress table, not from the request context. Since C1-5 the
        # temporary object is created INSIDE the pipeline, so the UI thread only learns its id
        # because the pipeline publishes it there the moment it has one - which it does precisely
        # for this case, since stopping the pipeline kills its own clean-up.
        # (The Context fallback covers a caller that knew the id up front.)
        $Private:TempQueryDoId = $Private:Pending.Progress.TempQueryDoId
        if ($null -eq $Private:TempQueryDoId) {
            $Private:TempQueryDoId = $Private:Pending.Context.Caller.TempQueryDoId
        }
        if ($null -ne $Private:TempQueryDoId) {
            "Removing the temporary query object left by the cancelled execution." | Write-LogOutput -LogType DEBUG
            Remove-SqlQueryObject -DoId $Private:TempQueryDoId
        }

        "Stopped waiting for the query. It may still be running on the server." | Write-LogOutput -LogType WARNING -SkipDialog
        $Script:MainForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "cancelled"

        Reset-ExecuteQueryUiState
    }
    catch {
        # Whatever went wrong, the tab must not be left in the executing state - that would leave the
        # user with a Cancel button that cancels nothing and no way back to Execute.
        Reset-ExecuteQueryUiState
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
