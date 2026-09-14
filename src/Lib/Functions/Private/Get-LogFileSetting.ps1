function Get-LogFileSetting {
    <#
    .SYNOPSIS
        Resolves the effective session log file settings from the global configuration.

    .DESCRIPTION
        Follows the shape Get-SqlValidationSetting and Get-ArrayCopySetting established: the stored
        value wins when it is usable, the schema default fills in for a configuration file written
        before these properties existed, and a hard fallback covers a schema that cannot be read at
        all. No call site repeats any of it.

        The five properties, as the maintainer set them for issue #121:

          EnableSessionLogFile            write a file for the session at all; off by default
          SessionLogFileLogLevel          the file's OWN level, independent of the log window's
          SessionLogFileDirectory         empty means "beside the other per-user state"
          SessionLogFileRetentionCount    keep at most this many sessions, the running one included
          SessionLogFileMaxSizeMegabytes  split the active file into a numbered part past this size

        Nothing here is allowed to resolve to zero from an unusable stored value. A zero retention
        would delete every other session, and a zero size would split the file after every line.

    .OUTPUTS
        [PSCustomObject] with Enabled, LogLevel, Directory, RetentionCount and MaxSizeMegabytes.

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

    # Off unless something says otherwise: a file on disk is opt-in.
    $Enabled = Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $false

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

    $RetentionCount = Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10
    $MaxSizeMegabytes = Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileMaxSizeMegabytes" -Fallback 5

    return [PSCustomObject]@{
        Enabled          = $Enabled
        LogLevel         = $LogLevel
        Directory        = $Directory
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
