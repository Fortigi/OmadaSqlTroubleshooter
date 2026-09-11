function Get-SqlValidationSetting {
    <#
    .SYNOPSIS
        Resolves the effective client-side validation settings from the global configuration.

    .DESCRIPTION
        Three things decide whether a pass runs, and they are resolved in one place so no call site
        has to repeat them:

          * the user's EnableSyntaxValidation, EnableSchemaValidation and
            EnableOmadaCompatibilityValidation settings, which are independent of each other
            (issue #61 acceptance criteria 7 and A8);
          * whether the ScriptDom assembly actually loaded ($Script:SqlSyntaxValidationAvailable,
            set once at startup by Initialize-OmadaSqlTroubleShooter) - all three passes read the
            same syntax tree, so without a parser none of them can run;
          * the schema defaults, for a configuration file written before these properties existed.

        A stored ValidationDebounceMilliseconds that is absent, -1 (the value Add-ConfigProperty
        writes for an Int with no default) or otherwise unusable falls back to the schema default
        rather than to zero, because zero would mean "validate on every keystroke".

    .OUTPUTS
        [PSCustomObject] with Enabled, SchemaEnabled, OmadaEnabled, DebounceMilliseconds,
        WarnOnExecuteWithErrors, ParserVersion and RuleSeverity.
    #>
    [CmdLetBinding()]
    param()

    # No tracer preamble: this is called from the debounced validation path on every idle tick.

    $Enabled = $true
    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.EnableSyntaxValidation) {
        $Enabled = [bool]$Script:AppGlobalConfig.EnableSyntaxValidation
    }

    $SchemaEnabled = $true
    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.EnableSchemaValidation) {
        $SchemaEnabled = [bool]$Script:AppGlobalConfig.EnableSchemaValidation
    }

    $OmadaEnabled = $true
    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.EnableOmadaCompatibilityValidation) {
        $OmadaEnabled = [bool]$Script:AppGlobalConfig.EnableOmadaCompatibilityValidation
    }

    # An unavailable parser overrides every setting: all three passes read the tree it produces, so
    # the feature cannot run whatever the user asked for. The single WARNING about that was already
    # emitted at startup.
    if ($Script:SqlSyntaxValidationAvailable -ne $true) {
        $Enabled = $false
        $SchemaEnabled = $false
        $OmadaEnabled = $false
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

    # Passed through as stored, not normalised here: Resolve-OmadaCompatibilityRuleSeverity is the one
    # place that decides what an override means, including what an unrecognised value means, and it
    # has the rule's own default in hand to fall back to.
    $RuleSeverity = $null
    if ($null -ne $Script:AppGlobalConfig -and $null -ne $Script:AppGlobalConfig.OmadaCompatibilityRuleSeverity) {
        $RuleSeverity = $Script:AppGlobalConfig.OmadaCompatibilityRuleSeverity
    }

    return [PSCustomObject]@{
        Enabled                 = $Enabled
        SchemaEnabled           = $SchemaEnabled
        OmadaEnabled            = $OmadaEnabled
        DebounceMilliseconds    = $Debounce
        WarnOnExecuteWithErrors = $WarnOnExecute
        ParserVersion           = $ParserVersion
        RuleSeverity            = $RuleSeverity
    }
}
