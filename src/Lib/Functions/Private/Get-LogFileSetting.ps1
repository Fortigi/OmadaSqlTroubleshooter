function Get-LogFileSetting {
    <#
    .SYNOPSIS
        Resolves the effective session log file settings from the global configuration.

    .DESCRIPTION
        Follows the shape Get-SqlValidationSetting and Get-ArrayCopySetting established: the stored
        value wins when it is usable, the schema default fills in for a configuration file written
        before these properties existed, and a hard fallback covers a schema that cannot be read at
        all. No call site repeats any of it.

        The six properties come from issue #121:

          EnableSessionLogFile            write a file for the session at all
          SessionLogFileLogLevel          the file's OWN level, independent of the log window's
          SessionLogFileDirectory         empty means "beside the other per-user state"
          SessionLogFileRetentionDays     prune sessions older than this on start-up
          SessionLogFileRetentionCount    keep at most this many sessions
          SessionLogFileMaxSizeMegabytes  ceiling per file, after which the session rolls to a part

        Nothing here is allowed to resolve to zero from an unusable stored value. A zero retention
        would delete the log the user is about to be asked for, and a zero ceiling would end the file
        after its first line - both of them the failure this feature exists to prevent, arrived at by
        a different route.

    .OUTPUTS
        [PSCustomObject] with Enabled, LogLevel, Directory, RetentionDays, RetentionCount and
        MaxSizeMegabytes.

    .EXAMPLE
        $Setting = Get-LogFileSetting

    .NOTES
        Called once per session, by Start-SessionLogFile, which caches the answer on
        $Script:SessionLogFile. Write-LogOutput must never call this: Get-ConfigSchemaDefault logs a
        WARNING for a property it cannot find, and Write-LogOutput calling something that logs would
        recurse.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject])]
    param()

    $Enabled = Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $true

    # Resolve-LogLevel is the module's one answer to "is this string a log level?", and it already
    # falls back from a stored value to the schema default without guessing. A level nobody can read
    # must not silently switch the file to a quieter one.
    $LogLevel = Resolve-LogLevel -PersistedLogLevel ([string]$Script:AppGlobalConfig.SessionLogFileLogLevel) -SchemaDefault ([string](Get-ConfigSchemaDefault -Property "SessionLogFileLogLevel"))
    if ([string]::IsNullOrWhiteSpace($LogLevel)) {
        $LogLevel = "DEBUG"
    }

    # Beside the configuration file and the persisted tabs, under the same AppDataFolder - which the
    # E2E lane redirects with OMADASQL_E2E_APPDATA, so an automated run writes its logs into its own
    # sandbox rather than the developer's profile.
    $Directory = $null
    if ($null -ne $Script:RunTimeConfig -and ![string]::IsNullOrWhiteSpace($Script:RunTimeConfig.AppDataFolder)) {
        $Directory = Join-Path $Script:RunTimeConfig.AppDataFolder -ChildPath "logs"
    }

    if ($null -ne $Script:AppGlobalConfig -and ![string]::IsNullOrWhiteSpace($Script:AppGlobalConfig.SessionLogFileDirectory)) {
        $Directory = [string]$Script:AppGlobalConfig.SessionLogFileDirectory
    }

    $RetentionDays = Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionDays" -Fallback 14
    $RetentionCount = Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 20
    $MaxSizeMegabytes = Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileMaxSizeMegabytes" -Fallback 20

    return [PSCustomObject]@{
        Enabled          = $Enabled
        LogLevel         = $LogLevel
        Directory        = $Directory
        RetentionDays    = $RetentionDays
        RetentionCount   = $RetentionCount
        MaxSizeMegabytes = $MaxSizeMegabytes
    }
}

function Resolve-SessionLogFileBooleanSetting {
    <#
    .SYNOPSIS
        Resolves one boolean session-log-file setting from the stored configuration, the schema
        default and a hard fallback, in that order.

    .PARAMETER Property
        The global configuration property name.

    .PARAMETER Fallback
        The value to use when neither the configuration nor the schema supplies one.

    .OUTPUTS
        [bool]
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Property,
        [Parameter(Mandatory = $true)]
        [bool]$Fallback
    )

    $Resolved = $Fallback

    # Resolve-StrictBoolean, not a [bool] cast. The cast is truthiness, so a hand-edited "false" in
    # the configuration file - a non-empty string - would read as $true and leave the file being
    # written for a user who had just switched it off.
    $SchemaDefault = Resolve-StrictBoolean -Value (Get-ConfigSchemaDefault -Property $Property)
    if ($null -ne $SchemaDefault) {
        $Resolved = $SchemaDefault
    }

    if ($null -ne $Script:AppGlobalConfig) {
        $Stored = Resolve-StrictBoolean -Value $Script:AppGlobalConfig.$Property
        if ($null -ne $Stored) {
            $Resolved = $Stored
        }
    }

    return $Resolved
}

function Resolve-SessionLogFileIntegerSetting {
    <#
    .SYNOPSIS
        Resolves one positive-integer session-log-file setting from the stored configuration, the
        schema default and a hard fallback, in that order.

    .DESCRIPTION
        Greater than zero, not "not null": Add-ConfigProperty writes -1 for an Int with no stored
        value, and none of these settings has a meaningful zero.

    .PARAMETER Property
        The global configuration property name.

    .PARAMETER Fallback
        The value to use when neither the configuration nor the schema supplies a usable one.

    .OUTPUTS
        [int]
    #>

    [CmdLetBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Property,
        [Parameter(Mandatory = $true)]
        [int]$Fallback
    )

    $Resolved = $Fallback

    $Parsed = 0
    $SchemaDefault = Get-ConfigSchemaDefault -Property $Property
    if ($null -ne $SchemaDefault -and [int]::TryParse([string]$SchemaDefault, [ref]$Parsed) -and $Parsed -gt 0) {
        $Resolved = $Parsed
    }

    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.$Property) {
        $Parsed = 0
        if ([int]::TryParse([string]$Script:AppGlobalConfig.$Property, [ref]$Parsed) -and $Parsed -gt 0) {
            $Resolved = $Parsed
        }
    }

    return $Resolved
}
