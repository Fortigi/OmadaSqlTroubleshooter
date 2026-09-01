function Resolve-LogLevel {
    <#
    .SYNOPSIS
    Resolves the log level that a session should run with, from the three candidates that can supply one.

    .DESCRIPTION
    Precedence is: an explicitly bound -LogLevel parameter, then the level persisted in the global
    configuration by the log viewer, then the default declared in the global configuration schema.
    A candidate that is empty, or that names a level the application does not know, is skipped
    rather than rejected, so a hand-edited or stale configuration file degrades to the default
    instead of failing the start-up path.

    .PARAMETER BoundLogLevel
    The value of the -LogLevel parameter, but only when the caller actually bound it.

    .PARAMETER PersistedLogLevel
    The level stored in the global configuration file by an earlier session.

    .PARAMETER SchemaDefault
    The default declared for LogLevel in the global configuration schema.
    #>
    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$BoundLogLevel,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$PersistedLogLevel,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SchemaDefault
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        # The levels the log viewer offers and Write-LogOutput understands. LOG is included because
        # the log viewer lets a user select it, so it is a legitimate persisted value.
        $KnownLogLevel = @("LOG", "INFO", "WARNING", "ERROR", "FATAL", "DEBUG", "VERBOSE", "VERBOSE2")

        foreach ($Candidate in @($BoundLogLevel, $PersistedLogLevel, $SchemaDefault)) {
            if ([string]::IsNullOrWhiteSpace($Candidate)) {
                continue
            }

            $NormalizedCandidate = $Candidate.Trim().ToUpperInvariant()
            if ($KnownLogLevel -contains $NormalizedCandidate) {
                return $NormalizedCandidate
            }
        }

        return $null
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
