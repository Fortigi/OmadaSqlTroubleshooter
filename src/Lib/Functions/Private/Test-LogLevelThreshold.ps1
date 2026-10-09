function Test-LogLevelThreshold {
    <#
    .SYNOPSIS
        Answers whether a message of a given log type survives a given log level.

    .DESCRIPTION
        The one inclusion table the application filters on. Write-LogOutput applied it inline until
        the session log file (issue #121) needed the same question answered, and two callers asking it
        needed one answer rather than two copies of the table that could drift.

        Both callers now pass the same level: the application's LogLevelSetting (issue #157). The file
        had a level of its own until then, which could be set quieter than the log window and silently
        drop from disk what the window was showing. Keeping the table here is what makes "the file
        shows exactly what the window shows" one implementation rather than a coincidence.

        The table is unchanged from the switch statement it replaces, including its default branch:
        a level the application does not know includes nothing at all.

    .PARAMETER Level
        The configured log level to filter at - the application's LogLevelSetting, which the log
        window, the console and the session log file all filter on.

    .PARAMETER LogType
        The type of the message being written.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-LogLevelThreshold -Level "WARNING" -LogType "DEBUG"
        False

    .NOTES
        No tracer preamble, and this function must never call Write-LogOutput: Write-LogOutput calls
        it for every single message, so either would recurse. The same rule governs
        Protect-LogMessage for the same reason.
    #>
    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Level,
        [Parameter(Mandatory = $true, Position = 1)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogType
    )

    if ([string]::IsNullOrWhiteSpace($Level) -or [string]::IsNullOrWhiteSpace($LogType)) {
        return $false
    }

    # A rank for the level and a rank for the log type, rather than a list of included types per
    # level: a message survives when its type's rank is no higher than the level's. It is the same
    # table the switch statement in Write-LogOutput applied - asserted for all 64 combinations - but
    # without building an array on every call, and this runs twice for every message written.
    $LevelRank = switch ($Level.Trim().ToUpperInvariant()) {
        "VERBOSE2" { 5 }
        "VERBOSE" { 4 }
        "DEBUG" { 3 }
        "INFO" { 2 }
        "WARNING" { 1 }
        "ERROR" { 0 }
        "FATAL" { 0 }
        # A level the application does not know includes nothing, as the switch's default branch did.
        default { -1 }
    }

    $LogTypeRank = switch ($LogType.Trim().ToUpperInvariant()) {
        "VERBOSE2" { 5 }
        "VERBOSE" { 4 }
        "DEBUG" { 3 }
        "INFO" { 2 }
        "WARNING" { 1 }
        "ERROR" { 0 }
        "FATAL" { 0 }
        "LOG" { 0 }
        # A log type the application does not emit survives no level.
        default { 6 }
    }

    return ($LogTypeRank -le $LevelRank)
}

function Test-LogTypeShown {
    <#
    .SYNOPSIS
        Answers whether a message of this log type would be shown at the application's log level.

    .DESCRIPTION
        For a caller whose MESSAGE is expensive to build. Write-LogOutput filters on the level itself,
        but only after the caller has formatted the message - and for the request and response lines
        that formatting is a redacting walk of the whole object, which for a SQL schema response took
        over a second on the UI thread whether the line was then shown or not. Asking first lets the
        caller skip building what nobody will see.

    .PARAMETER LogType
        The type the message would be written at.

    .OUTPUTS
        [bool] $false when no log level is configured.

    .NOTES
        No tracer preamble and no Write-LogOutput, for the reason Test-LogLevelThreshold gives.
    #>
    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$LogType
    )

    return Test-LogLevelThreshold -Level ([string]$Script:RunTimeConfig.Logging.LogLevelSetting) -LogType $LogType
}
