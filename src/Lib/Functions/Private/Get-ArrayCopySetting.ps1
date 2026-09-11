function Get-ArrayCopySetting {
    <#
    .SYNOPSIS
        Resolves the effective "Copy as SQL/PowerShell array" settings from the global configuration.

    .DESCRIPTION
        Follows the shape Get-SqlValidationSetting established: the stored value wins when it is
        usable, the schema default fills in for a configuration file written before these
        properties existed, and a hard fallback covers a schema that cannot be read at all. No call
        site repeats any of it.

        The four properties come from issue #103 section 5:

          ArrayCopyUseColumnSchema          resolved types, or the pre-#103 text sniffing
          ArrayCopyPowerShellTypedLiterals  [datetime]'...' / [guid]'...' vs plain quoted strings
          ArrayCopyNullHandling             Emit ($null / NULL) or Skip
          ArrayCopyMaxValues                warn above this many values

    .OUTPUTS
        [PSCustomObject] with UseColumnSchema, PowerShellTypedLiterals, NullHandling and MaxValues.

    .EXAMPLE
        $Setting = Get-ArrayCopySetting

    .NOTES
        No tracer preamble: this is called from the clipboard path, which the user can trigger by
        held-down keyboard shortcut.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject])]
    param()

    $UseColumnSchema = Resolve-ArrayCopyBooleanSetting -Property "ArrayCopyUseColumnSchema" -Fallback $true
    $TypedLiterals = Resolve-ArrayCopyBooleanSetting -Property "ArrayCopyPowerShellTypedLiterals" -Fallback $true

    $NullHandling = "Emit"
    $NullDefault = Get-ConfigSchemaDefault -Property "ArrayCopyNullHandling"
    if (![string]::IsNullOrWhiteSpace($NullDefault)) {
        $NullHandling = [string]$NullDefault
    }

    if ($null -ne $Script:AppGlobalConfig -and ![string]::IsNullOrWhiteSpace($Script:AppGlobalConfig.ArrayCopyNullHandling)) {
        $NullHandling = [string]$Script:AppGlobalConfig.ArrayCopyNullHandling
    }

    # Anything unrecognised means Emit. Dropping values because a setting was misspelled would make
    # the copied list quietly shorter than the selection.
    if ($NullHandling -notin @("Emit", "Skip")) {
        $NullHandling = "Emit"
    }

    $MaxValues = 1000
    $MaxDefault = Get-ConfigSchemaDefault -Property "ArrayCopyMaxValues"
    $ParsedDefault = 0
    if ($null -ne $MaxDefault -and [int]::TryParse([string]$MaxDefault, [ref]$ParsedDefault) -and $ParsedDefault -gt 0) {
        $MaxValues = $ParsedDefault
    }

    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.ArrayCopyMaxValues) {
        $Stored = 0
        # Greater than zero, not "not null": Add-ConfigProperty writes -1 for an Int with no stored
        # value, and a zero or negative threshold would warn on every single copy.
        if ([int]::TryParse([string]$Script:AppGlobalConfig.ArrayCopyMaxValues, [ref]$Stored) -and $Stored -gt 0) {
            $MaxValues = $Stored
        }
    }

    return [PSCustomObject]@{
        UseColumnSchema         = $UseColumnSchema
        PowerShellTypedLiterals = $TypedLiterals
        NullHandling            = $NullHandling
        MaxValues               = $MaxValues
    }
}

function Resolve-ArrayCopyBooleanSetting {
    <#
    .SYNOPSIS
        Resolves one boolean array-copy setting from the stored configuration, the schema default
        and a hard fallback, in that order.

    .PARAMETER Property
        The global configuration property name.

    .PARAMETER Fallback
        The value to use when neither the configuration nor the schema supplies one.

    .OUTPUTS
        [bool]

    .NOTES
        No tracer preamble: called from the clipboard path.
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

    # Resolve-StrictBoolean, not a [bool] cast. The cast is truthiness: a hand-edited "false" in the
    # configuration file is a non-empty string, so [bool] would read it as $true and switch the
    # setting ON precisely when the user wrote that they wanted it off. An unparseable value keeps
    # the previous step's answer instead of silently inverting it.
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
