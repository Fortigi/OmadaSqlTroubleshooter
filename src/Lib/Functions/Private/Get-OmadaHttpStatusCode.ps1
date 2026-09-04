function Get-OmadaHttpStatusCode {
    <#
    .SYNOPSIS
    Pull the HTTP status code out of an error, or return $null when the error is not an HTTP response.

    .DESCRIPTION
    The presence of a status code is the discriminator the execute fallback rests on: if a status came
    back, a round trip completed, so whatever went wrong is the tenant's answer rather than a broken
    worker (see Resolve-ExecuteFallbackAction).

    Two sources, in order. The exception's own Response.StatusCode is authoritative when it survives -
    but an error that has crossed a runspace boundary has usually been flattened to text by then, so
    the message is parsed as a fallback. That is the form the worker's failures actually arrive in:

        Response status code does not indicate success: 502 (Bad Gateway).

    .PARAMETER ErrorRecord
    The error to inspect. $null is accepted and yields $null.

    .OUTPUTS
    [int] the status code, or $null when there is none to be found.
    #>
    [CmdLetBinding()]
    param(
        $ErrorRecord
    )

    if ($null -eq $ErrorRecord) {
        return $null
    }

    try {
        $Private:Response = $ErrorRecord.Exception.Response
        if ($null -ne $Private:Response -and $null -ne $Private:Response.StatusCode) {
            return [int]$Private:Response.StatusCode
        }
    }
    catch {
        # Not an HTTP exception, or the property is not reachable. The message is tried next.
    }

    try {
        $Private:Match = [regex]::Match([string]$ErrorRecord.Exception.Message, "status code does not indicate success:\s*(\d{3})")
        if ($Private:Match.Success) {
            return [int]$Private:Match.Groups[1].Value
        }
    }
    catch {
        # A message that cannot be read is simply not a status code.
    }

    return $null
}
