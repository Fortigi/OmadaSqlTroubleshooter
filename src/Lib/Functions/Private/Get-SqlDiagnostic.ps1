function Get-SqlDiagnostic {
    <#
    .SYNOPSIS
        Runs the client-side validation passes over a script and returns everything they found, on
        one diagnostics channel.

    .DESCRIPTION
        The single entry point issue #61 section 3 asks for. The script is parsed ONCE and the tree is
        handed to each enabled pass:

            T-SQL syntax           ScriptDom parse errors, Error, exactly SQL Server's wording
            SQL schema             identifiers resolved against the already-cached schema, Warning
            Omada compatibility    the rule catalogue, severities from the rule table and config

        Each pass is switched on independently (acceptance criterion 7 and A8), and with ScriptDom
        unavailable all three are off and the application behaves exactly as it did before the feature
        existed (acceptance criterion 6 and A8).

        Nothing here contacts Omada. The schema pass reads the cache the editor's IntelliSense already
        filled, and makes no request of its own (acceptance criterion 5).

        The schema pass is skipped when the script did not parse cleanly. A partial tree from a
        recovered parse names identifiers the user has not finished typing, and resolving those
        produces a warning under the cursor on every keystroke - the exact noise that gets a pass
        switched off. The syntax error is the useful thing to say about that script anyway.

    .PARAMETER SqlText
        The script to check.

    .PARAMETER Setting
        The resolved settings from Get-SqlValidationSetting. Omit to resolve them here.

    .PARAMETER SchemaModel
        The indexed schema to resolve against. Omit to take the active tab's, which is what every
        caller in the application wants; tests pass one explicitly.

    .OUTPUTS
        [PSCustomObject] with

            Status         Ok          the script was checked
                           Unavailable nothing was parsed, so nothing was checked
                           Disabled    every pass is switched off
            Diagnostic     the markers from every enabled pass, ordered by position
            ParserVersion  the parser used, or $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Setting,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $SchemaModel
    )

    # No tracer preamble: $SqlText is the user's query (issue #61 section 5).

    if ($null -eq $Setting) {
        $Setting = Get-SqlValidationSetting
    }

    if (-not $Setting.Enabled -and -not $Setting.SchemaEnabled -and -not $Setting.OmadaEnabled) {
        return [PSCustomObject]@{
            Status        = "Disabled"
            Diagnostic    = @()
            ParserVersion = $null
        }
    }

    $Parsed = Get-SqlScriptFragment -SqlText $SqlText -ParserVersion $Setting.ParserVersion

    if ($Parsed.Status -ne "Ok") {
        return [PSCustomObject]@{
            Status        = "Unavailable"
            Diagnostic    = @()
            ParserVersion = $null
        }
    }

    $Diagnostic = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($Setting.Enabled) {
        foreach ($Item in @(ConvertTo-SqlSyntaxDiagnostic -ParseError $Parsed.ParseError -SqlText $SqlText)) {
            $Diagnostic.Add($Item)
        }
    }

    $ParsedCleanly = (@($Parsed.ParseError).Count -eq 0)

    if ($Setting.SchemaEnabled -and $ParsedCleanly) {
        if (-not $PSBoundParameters.ContainsKey("SchemaModel")) {
            $SchemaModel = Get-ActiveSqlSchemaModel
        }

        foreach ($Item in @(Get-SqlSchemaDiagnostic -Fragment $Parsed.Fragment -SchemaModel $SchemaModel)) {
            $Diagnostic.Add($Item)
        }
    }

    if ($Setting.OmadaEnabled -and $ParsedCleanly) {
        foreach ($Item in @(Get-OmadaCompatibilityDiagnostic -Fragment $Parsed.Fragment -RuleSeverity $Setting.RuleSeverity)) {
            $Diagnostic.Add($Item)
        }
    }

    return [PSCustomObject]@{
        Status        = "Ok"
        Diagnostic    = @($Diagnostic | Sort-Object -Property @{ Expression = { [int]$_.Line } }, @{ Expression = { [int]$_.Column } })
        ParserVersion = $Parsed.ParserVersion
    }
}

function Test-SqlDiagnosticBlocksExecution {
    <#
    .SYNOPSIS
        Decides whether a diagnostic takes part in the "execute anyway?" confirmation.

    .DESCRIPTION
        Issue #61 puts the three passes in three different places on purpose, and this is where that
        decision is written down:

          * A SYNTAX error is a batch SQL Server will reject before it touches a table. It asks.
          * An OMADA COMPATIBILITY diagnostic at Error or Warning is a deterministic wrong outcome -
            a statement that cannot run here, or a result set that will arrive empty. It asks
            (section 3.5). At Info it is an observation about naming, and it does not.
          * A SCHEMA warning is a guess against a cache that may be stale and a schema whose coverage
            is not guaranteed. It never asks, and never gates execution (acceptance criterion 4).

        Nothing here ever blocks. The answer only decides whether the user is asked once.

        The Source labels are matched as literals, and they are the same literals each pass declares
        as its own Source default. They are part of the diagnostics contract in issue #61 section 3 -
        the editor shows them in the marker hover - so they are written out here rather than hidden
        behind a shared constant that a test could leave undefined.

    .PARAMETER Diagnostic
        The diagnostic to classify.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        $Diagnostic
    )

    process {
        if ($null -eq $Diagnostic) {
            return $false
        }

        switch ([string]$Diagnostic.Source) {
            "T-SQL syntax" { return $true }
            "Omada compatibility" { return ([string]$Diagnostic.Severity -in @("Error", "Warning")) }
            default { return $false }
        }
    }
}
