function Get-OmadaWritePermissionMessage {
    <#
    .SYNOPSIS
    Explain a refused OData write as the missing permission it almost certainly is, or return $null
    when the failure is something else.

    .DESCRIPTION
    Omada's OData endpoint authorizes every request against the 'OData' auth element of the signed-in
    account: POST needs Create, GET needs Read, PUT needs Update and DELETE needs Delete
    (ODataControllerBase.Authorize). A missing right is answered with HTTP 401 - not 403 - and
    OmadaWeb.PS turns a 401 into its "session expired" error. So an account that may read queries but
    not write them was told to sign in again, which can never help.

    Seen on a live tenant: executing a whole saved query worked, because that only reads the query
    object and runs it through an ASMX web service that the OData rights do not cover. Executing a
    selection failed, because a selection runs through a temporary TMP_<guid> query object that has to
    be created, updated and deleted through OData.

    The distinguishing evidence is ORDER. A 401 on a write, after requests in the same run already
    came back successfully moments before, is not an expired session: the session demonstrably
    worked. That is the only case this function claims; everything else returns $null and keeps the
    existing report.

    Pure on purpose - no $Script: state, no logging - so it can be tested on its own and called from
    any completion path.

    .PARAMETER Outcome
    A pipeline outcome from Invoke-OmadaExecutePipeline: FailedStep, ErrorRecord, CompletedSteps and
    Steps (an ordered list of @{ Name; Method; Uri }).

    .OUTPUTS
    [string] the message for the user, or $null when the failure is not a refused OData write.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        $Outcome
    )

    # A missing ErrorRecord or FailedStep needs no guard of its own: no recorded step matches an empty
    # name, and a missing error is neither a session expiry nor a 401.
    if ($null -eq $Outcome) {
        return $null
    }

    # Nothing came back yet, so a refusal could be a genuinely expired session. Only a run that has
    # already talked to the tenant successfully proves the session itself was fine.
    if ([int]$Outcome.CompletedSteps -le 0) {
        return $null
    }

    # The FIRST step with the failed step's name: a multi-statement run repeats step names, and the
    # step that failed first is the one the outcome's FailedStep describes.
    $Private:FailedRequest = @($Outcome.Steps) | Where-Object { $null -ne $_ -and $_.Name -eq $Outcome.FailedStep } | Select-Object -First 1
    if ($null -eq $Private:FailedRequest) {
        return $null
    }

    # Only OData requests are authorized against the OData auth element. The ASMX web services
    # (execute, undelete) are not, and their 401 means something this function cannot explain.
    if ([string]$Private:FailedRequest.Uri -notmatch "/odata/") {
        return $null
    }

    $Private:PermissionByMethod = @{
        POST   = "Create"
        PUT    = "Update"
        DELETE = "Delete"
    }
    $Private:Method = ([string]$Private:FailedRequest.Method).ToUpperInvariant()
    if (-not $Private:PermissionByMethod.ContainsKey($Private:Method)) {
        return $null
    }

    $Private:IsRefused = (Test-OmadaSessionExpiredError -ErrorRecord $Outcome.ErrorRecord) -or
    ((Get-OmadaHttpStatusCode -ErrorRecord $Outcome.ErrorRecord) -eq 401)
    if (-not $Private:IsRefused) {
        return $null
    }

    $Private:Permission = $Private:PermissionByMethod[$Private:Method]
    $Private:Action = switch ($Private:Permission) {
        "Create" { "create" }
        "Update" { "update" }
        "Delete" { "delete" }
    }

    return ("Omada refused to {0} a SQL troubleshooting query (HTTP 401), although this session read from the tenant successfully moments before. " +
        "Omada's OData answers a missing permission with 401, so your account most likely lacks the '{1}' permission on the 'OData' auth element. " +
        "Executing a selection or several statements needs Read, Create, Update and Delete; saving a changed query needs Update. " +
        "Ask an Omada administrator to grant these permissions; signing in again will not help.") -f $Private:Action, $Private:Permission
}
