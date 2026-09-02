function Test-OmadaBackgroundRequestEligible {
    <#
    .SYNOPSIS
    Decide whether a request may be dispatched to a background worker, or must run on the UI thread.

    .DESCRIPTION
    This is where issue #40's authentication policy is expressed: interactive authentication happens
    on the UI thread, or it does not happen.

    OmadaWeb.PS authenticates by opening a WinForms modal on whatever thread calls it. From a worker
    that dialog would have no owner window - not modal to this app, possibly behind the main window,
    with the app fully interactive behind it. So off-thread execution is only ever offered for a
    session that is ALREADY authenticated, where OmadaWeb.PS answers from its encrypted on-disk
    cookie cache and never opens a window at all.

    Two conditions, and both are about that:

      - The tab must be connected. $Script:ConnectionStatus is set only by Set-SqlConnectionState
        after Test-OmadaConnection succeeded, which is the UI-thread path where a login prompt is
        shown with a proper owner. A connected tab therefore has a cookie on disk for its SessionKey,
        which a fresh worker runspace - whose own OmadaWeb.PS session table is empty - will load.

      - ForceAuthentication must not be set. That flag exists to make OmadaWeb.PS bypass the cookie
        cache and re-authenticate, which is a request to open the login window. It must be honoured
        on the UI thread.

    .NOTES
    This is a gate, not a guarantee. A cookie that expires between connecting and issuing a
    background request would still send the worker down the authentication path - where the MTA
    apartment of the pool (see Initialize-OmadaRequestPool) turns it into a clean failure rather than
    an ownerless window, and the failure comes back to the UI thread to be re-driven. That residual
    case is only observable against a live tenant: the mock replaces Invoke-OmadaRestMethod outright,
    so no authentication ever happens under test.

    .PARAMETER Parameters
    The prepared Invoke-OmadaRestMethod splat for the request being considered.

    .OUTPUTS
    [bool] - $true when the request may go to a worker.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    if (-not $Script:ConnectionStatus) {
        return $false
    }

    if ($true -eq $Parameters.ForceAuthentication) {
        return $false
    }

    return $true
}
