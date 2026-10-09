function Write-RedactedRequestLog {
    <#
    .SYNOPSIS
        Logs a request's parameters or a response, redacted, at the detail the log level asks for.

    .DESCRIPTION
        The "Parameters: ..." and "Result: ..." lines of both request wrappers. They were written at
        VERBOSE in full, which for a SQL schema response meant hundreds of lines naming every table in
        the customer's database, and over a second on the UI thread per large database to build them -
        built even at a level that would not show them.

          VERBOSE2 shown  the full redacted object, at VERBOSE2 - what VERBOSE used to show.
          VERBOSE shown   the same, except that an object with more than $MaxProperties members is
                          summarised by its count ("Object with 565 properties"): ordinary requests and
                          responses read exactly as before, a schema response is one line.
          otherwise       nothing is built at all.

        Not in ConvertTo-RedactedLogString.ps1: that file may never call Write-LogOutput (see there).

    .PARAMETER Label
        "Parameters" or "Result" - the start of the line.

    .PARAMETER InputObject
        What to log.

    .PARAMETER MaxProperties
        The member count above which VERBOSE summarises an object.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $false)]
        [int]$MaxProperties = 50
    )

    # No tracer preamble: called for every request, and the object it logs is the request itself.

    if (Test-LogTypeShown -LogType VERBOSE2) {
        "{0}: {1}" -f $Label, (ConvertTo-RedactedLogString -InputObject $InputObject) | Write-LogOutput -LogType VERBOSE2
        return
    }

    if (Test-LogTypeShown -LogType VERBOSE) {
        "{0}: {1}" -f $Label, (ConvertTo-RedactedLogString -InputObject $InputObject -MaxProperties $MaxProperties) | Write-LogOutput -LogType VERBOSE
    }
}
