function Test-LogLevelThreshold {
    <#
    .SYNOPSIS
        Answers whether a message of a given log type survives a given log level.

    .DESCRIPTION
        The one inclusion table the application filters on. Write-LogOutput applied it inline for a
        single level - the log window's - which was enough until the session log file (issue #121)
        gained a level of its own that may reasonably be more verbose than the window's. Two callers
        asking the same question needed one answer, not two copies of the table that could drift.

        The table is unchanged from the switch statement it replaces, including its default branch:
        a level the application does not know includes nothing at all.

    .PARAMETER Level
        The configured log level to filter at, for example the log window's LogLevelSetting or the
        session log file's own level.

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
