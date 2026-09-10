function Get-ActiveExecuteQueryRequest {
    <#
    .SYNOPSIS
    The in-flight execute request belonging to a tab, or $null when that tab is not executing.

    .DESCRIPTION
    Read straight off the completion queue rather than from a per-tab "IsExecuting" flag, for the
    same reason Get-SqlSchemaObject checks the queue for a schema fetch: a flag has to be cleared on
    every path a request can leave by - success, failure, cancellation, and abandonment when its tab
    is closed - and one missed path leaves a tab that can never execute again. The queue is the
    single record of what is outstanding and cannot get out of step with itself.

    Cancelled items are excluded: the pipeline may take a moment to stop, but as far as the UI is
    concerned that request is over the instant the user asked for it to be.

    .PARAMETER TabSession
    The tab to ask about. Defaults to the active one.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    if ($null -eq $TabSession) {
        $TabSession = Get-ActiveTabSession
    }
    if ($null -eq $TabSession -or $null -eq $Script:PendingWebViewCompletions) {
        return $null
    }

    return @($Script:PendingWebViewCompletions | Where-Object {
            $_.Description -eq $Script:ExecuteQueryRequestDescription -and
            $null -ne $_.TabSession -and
            $_.TabSession.Id -eq $TabSession.Id -and
            -not $_.IsCancelled
        }) | Select-Object -First 1
}
