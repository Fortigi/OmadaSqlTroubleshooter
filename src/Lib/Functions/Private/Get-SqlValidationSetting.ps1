function Get-SqlValidationSetting {
    <#
    .SYNOPSIS
        Resolves the effective client-side validation settings from the global configuration.

    .DESCRIPTION
        Three things decide whether the syntax pass runs, and they are resolved in one place so no
        call site has to repeat them:

          * the user's EnableSyntaxValidation setting;
          * whether the ScriptDom assembly actually loaded ($Script:SqlSyntaxValidationAvailable,
            set once at startup by Initialize-OmadaSqlTroubleShooter);
          * the schema defaults, for a configuration file written before these properties existed.

        A stored ValidationDebounceMilliseconds that is absent, -1 (the value Add-ConfigProperty
        writes for an Int with no default) or otherwise unusable falls back to the schema default
        rather than to zero, because zero would mean "validate on every keystroke".

    .OUTPUTS
        [PSCustomObject] with Enabled, DebounceMilliseconds, WarnOnExecuteWithErrors and
        ParserVersion.
    #>
    [CmdLetBinding()]
    param()

    # No tracer preamble: this is called from the debounced validation path on every idle tick.

    $Enabled = $true
    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.EnableSyntaxValidation) {
        $Enabled = [bool]$Script:AppGlobalConfig.EnableSyntaxValidation
    }

    # An unavailable parser overrides the setting: the feature cannot run, whatever the user asked
    # for. The single WARNING about that was already emitted at startup.
    if ($Script:SqlSyntaxValidationAvailable -ne $true) {
        $Enabled = $false
    }

    $DebounceDefault = Get-ConfigSchemaDefault -Property "ValidationDebounceMilliseconds"
    if ($null -eq $DebounceDefault -or [int]$DebounceDefault -lt 1) {
        $DebounceDefault = 400
    }

    $Debounce = [int]$DebounceDefault
    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.ValidationDebounceMilliseconds) {
        $Stored = 0
        if ([int]::TryParse([string]$Script:AppGlobalConfig.ValidationDebounceMilliseconds, [ref]$Stored) -and $Stored -ge 1) {
            $Debounce = $Stored
        }
    }

    $WarnOnExecute = $true
    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.WarnOnExecuteWithErrors) {
        $WarnOnExecute = [bool]$Script:AppGlobalConfig.WarnOnExecuteWithErrors
    }

    $ParserVersion = $null
    if ($null -ne $Script:AppGlobalConfig -and ![string]::IsNullOrWhiteSpace($Script:AppGlobalConfig.SqlParserVersion)) {
        $ParserVersion = [string]$Script:AppGlobalConfig.SqlParserVersion
    }

    return [PSCustomObject]@{
        Enabled                 = $Enabled
        DebounceMilliseconds    = $Debounce
        WarnOnExecuteWithErrors = $WarnOnExecute
        ParserVersion           = $ParserVersion
    }
}
