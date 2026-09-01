function Set-BodyRedactionState {
    <#
    .SYNOPSIS
        Single writer of the "show request body" option.

    .DESCRIPTION
        Three places can turn the option on - the -SkipBodyRedaction parameter at start-up, the
        persisted setting restored when the log viewer opens, and the "Show request body" checkbox -
        and all three have to end up in the same state, so they all come through here.

        The authoritative value lives in $Script:SkipBodyRedaction, which ConvertTo-RedactedLogString
        reads from module scope (the same shape OmadaWeb.PS uses for its own -SkipBodyRedaction), and
        is mirrored into $Script:RunTimeConfig.Logging so the rest of the application can read it the
        way it reads every other logging setting.

        Switching the option on writes one WARNING, once per session: from that point the query text
        is in the log window and in anything exported from it, and a user attaching a log to a support
        ticket should not have to discover that afterwards.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [bool]$Enabled
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $Script:SkipBodyRedaction = $Enabled
        if ($null -ne $Script:RunTimeConfig -and $null -ne $Script:RunTimeConfig.Logging) {
            $Script:RunTimeConfig.Logging.SkipBodyRedaction = $Enabled
        }

        if ($Enabled) {
            if (-not $Script:SkipBodyRedactionWarned) {
                $Script:SkipBodyRedactionWarned = $true
                # -SkipDialog on purpose: this is a heads-up that belongs in the log the user is
                # looking at, not a modal box in front of the query they are trying to run.
                "Request body logging is enabled: query text is now written to this log in full, and to any log file exported from it." | Write-LogOutput -LogType WARNING -SkipDialog
            }

            "Request body logging is enabled" | Write-LogOutput -LogType LOG
        }
        else {
            "Request body logging is disabled" | Write-LogOutput -LogType LOG
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
