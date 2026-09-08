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

    This used to be one-way for the session, on the reasoning that whether a worker can authenticate
    is a property of the tenant and the authentication option rather than of the moment. A live
    session disproved that. Background execution ran for nine minutes, the application then sat idle
    for seventy, and the first query after the idle failed because the session had expired - which a
    worker cannot recover from, since it has no way to sign in. The UI thread re-authenticated
    seconds later and everything worked again, but background execution stayed off for the rest of
    the session for no reason.

    So it is now recoverable: Enable-OmadaBackgroundRequest turns it back on when a request has
    demonstrably succeeded on the UI thread, because that proves a session exists again for a worker
    to inherit. See there for how flapping is bounded.

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

    # The pool's workers are of no further use, and they are real threads. Initialize-OmadaRequestPool
    # rebuilds one on demand, so closing it here does not stand in the way of re-enabling later.
    Close-OmadaRequestPool
}

function Enable-OmadaBackgroundRequest {
    <#
    .SYNOPSIS
    Allow background execution again after a request has succeeded on the UI thread.

    .DESCRIPTION
    The disable exists to stop paying a doomed round-trip before every query. But the commonest
    reason for it is an expired session, which is a property of the moment and not of the tenant: a
    worker cannot sign in, so it fails; the UI thread signs in seconds later; and from then on there
    is a live session for a worker to inherit through the cookie cache.

    A request that has just succeeded on the UI thread is the proof that such a session exists, which
    is why that is the trigger. Nothing probes speculatively.

    Bounded, because the disable might instead be a worker that genuinely cannot ever run here - no
    WebView2 runtime, say - and re-enabling that costs one failed request each time. After
    $Script:OmadaBackgroundRequestReenableLimit attempts the session settles into disabled and stops
    trying. Three is enough to ride out a few session expiries in a working setup, and cheap enough
    in a broken one: three wasted round-trips across a whole session, not one per query.

    Restarting the application resets the count, as it always did.
    #>
    [CmdletBinding()]
    param()

    if (-not $Script:OmadaBackgroundRequestsDisabled) {
        return
    }

    if ($null -eq $Script:OmadaBackgroundRequestReenableLimit) {
        $Script:OmadaBackgroundRequestReenableLimit = 3
    }

    if ([int]$Script:OmadaBackgroundRequestReenableCount -ge $Script:OmadaBackgroundRequestReenableLimit) {
        # Said once, at DEBUG: the user was already told when it was disabled, and this is the
        # detail of a decision they cannot act on.
        if (-not $Script:OmadaBackgroundRequestReenableExhausted) {
            $Script:OmadaBackgroundRequestReenableExhausted = $true
            "Background query execution has failed {0} times after re-enabling; leaving it off for the rest of this session." -f $Script:OmadaBackgroundRequestReenableCount | Write-LogOutput -LogType DEBUG
        }
        return
    }

    $Script:OmadaBackgroundRequestReenableCount = [int]$Script:OmadaBackgroundRequestReenableCount + 1
    $Script:OmadaBackgroundRequestsDisabled = $false

    # INFO rather than a dialog: it is good news about something the user was told had gone away, so
    # it belongs in the log where the warning was - but it interrupts nothing.
    "A query succeeded on the UI thread, so background execution is available again. The window will stay responsive during a query." | Write-LogOutput -LogType INFO -SkipDialog
}
