function Disable-OmadaBackgroundRequest {
    <#
    .SYNOPSIS
    Stop offering background execution for the rest of this session, and say so once.

    .DESCRIPTION
    Issue #40 assumed that a tab which authenticated on the UI thread can also be served from a
    worker runspace, because OmadaWeb.PS keeps an encrypted cookie cache on disk and a fresh worker
    would load it. Live-tenant testing showed that is not universally true: with some tenants and
    authentication options the worker's own OmadaWeb.PS instance cannot establish a session at all,
    and every background request fails.

    That assumption was never testable - the mock replaces Invoke-OmadaRestMethod outright, so no
    authentication ever happens under test - so rather than keep guessing at it, eligibility is now
    settled by OBSERVATION. The first background request that fails without reaching the tenant calls
    this, and from then on Test-OmadaBackgroundRequestEligible refuses to dispatch: every later
    request goes straight down the synchronous path that has always worked, with no doomed round-trip
    in front of it.

    Deliberately session-scoped and one-way. Whether a worker can authenticate is a property of the
    tenant and the authentication option, not of the moment, so re-probing it per query would cost a
    failed request every time for an answer that will not have changed. Restarting the application
    re-probes.

    .PARAMETER Reason
    What went wrong, included in the single warning this writes.
    #>
    [CmdLetBinding()]
    param(
        [string]$Reason
    )

    if ($Script:OmadaBackgroundRequestsDisabled) {
        return
    }

    $Script:OmadaBackgroundRequestsDisabled = $true

    # WARNING, once, and not a dialog: nothing is broken from the user's point of view - the query
    # they asked for is about to run on the UI thread and succeed. What they lose is the window
    # staying responsive while it does, and that is worth one line in the log rather than a popup
    # interrupting them.
    "Background query execution is not available for this connection; falling back to running queries on the UI thread for the rest of this session. The window will not stay responsive during a query. Reason: {0}" -f $Reason | Write-LogOutput -LogType WARNING -SkipDialog

    # The pool's workers are of no further use, and they are real threads.
    Close-OmadaRequestPool
}
