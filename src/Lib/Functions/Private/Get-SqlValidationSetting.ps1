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

    $Enabled = Resolve-SqlValidationSwitch -Property "EnableSyntaxValidation"
    $SchemaEnabled = Resolve-SqlValidationSwitch -Property "EnableSchemaValidation"
    $OmadaEnabled = Resolve-SqlValidationSwitch -Property "EnableOmadaCompatibilityValidation"

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

    $WarnOnExecute = Resolve-SqlValidationSwitch -Property "WarnOnExecuteWithErrors"

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

function Resolve-SqlValidationSwitch {
    <#
    .SYNOPSIS
        Reads one of the validation on/off settings from the global configuration, strictly.

    .DESCRIPTION
        A plain [bool] cast is the wrong tool for a value that came out of a JSON file a user can
        hand-edit. PowerShell casts any non-empty string to $true, so a configuration containing

            "EnableSchemaValidation": "false"

        - quoted, which is an easy thing to type - would read as $true and leave the pass running for
        a user who had just switched it off. Being unable to turn a noisy check off is worse than the
        noise, and it is the failure this whole feature is written to avoid.

        So the value is parsed rather than coerced: a real boolean is taken as it is, the strings
        "true" and "false" are accepted in any casing, and anything else keeps the schema default.
        Keeping the DEFAULT rather than falling to $false matters - an unreadable value must not
        silently disable a check either, and the same rule already governs
        ValidationDebounceMilliseconds above.

    .PARAMETER Property
        The global configuration property to read. Its default comes from the schema, so the default
        lives in exactly one place.

    .OUTPUTS
        [bool]
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Property
    )

    # No tracer preamble: called from the debounced validation path on every idle tick.

    $Default = Get-ConfigSchemaDefault -Property $Property
    $Value = if ($null -eq $Default) { $true } else { [bool]$Default }

    if ($null -eq $Script:AppGlobalConfig -or $null -eq $Script:AppGlobalConfig.$Property) {
        return $Value
    }

    $Stored = $Script:AppGlobalConfig.$Property

    if ($Stored -is [bool]) {
        return $Stored
    }

    $Parsed = $false
    if ([bool]::TryParse([string]$Stored, [ref]$Parsed)) {
        return $Parsed
    }

    # Unreadable. The name is safe to log - it is a setting, not anything from the user's query.
    "Configuration property '{0}' is not a boolean; using the default." -f $Property | Write-LogOutput -LogType DEBUG

    return $Value
}
