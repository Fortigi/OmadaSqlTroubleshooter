function Get-SqlSyntaxDiagnostic {
    <#
    .SYNOPSIS
        Parses a T-SQL script with ScriptDom and returns the parse errors as editor diagnostics.

    .DESCRIPTION
        The first of the three validation passes described in issue #61. Everything here is local:
        ScriptDom is the parser SQL Server's own tooling uses, so a parse error carries the wording
        the server would have returned, without the round trip and without the opaque
        "External error (ref. no. ...)" that a server-side failure comes back as.

        The result is a status object rather than a bare collection, because "no diagnostics" and
        "could not look" are different answers and callers must be able to tell them apart:

            Status         Ok          the script was parsed; Diagnostic holds what came back
                           Unavailable ScriptDom is not loaded, so nothing was parsed
            Diagnostic     the parse errors, as marker-shaped objects; empty for a clean or empty
                           script, and always empty when Status is not Ok
            ParserVersion  the TSqlNNNParser actually used, or $null

        Unavailable is a return value, never an exception. This dependency is optional by design
        (issue #61 acceptance criterion 6): with it missing the application must behave exactly as it
        did before the feature existed.

        The application itself reaches the syntax pass through Get-SqlDiagnostic, which parses once
        and feeds all three passes from the same tree. This function stays because the syntax pass is
        meaningful on its own - and because it is the narrowest thing to test.

    .PARAMETER SqlText
        The script to parse. Null, empty and whitespace-only input are valid and yield no
        diagnostics - an empty editor is not a syntax error.

    .PARAMETER ParserVersion
        An explicit TSqlNNNParser to use. Omit to take the newest parser the loaded assembly ships.

    .PARAMETER Source
        The value written to each diagnostic's Source field, which the editor shows next to the
        message and which distinguishes this pass from the other two that share the same diagnostics
        channel.

    .OUTPUTS
        [PSCustomObject] with Status, Diagnostic and ParserVersion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ParserVersion,
        [Parameter(Mandatory = $false)]
        [string]$Source = "T-SQL syntax"
    )

    # DELIBERATELY no $Script:Tracer preamble. Every other function in this module opens with one,
    # which writes ConvertTo-RedactedLogString -InputObject $PSBoundParameters. Here $PSBoundParameters
    # IS the user's query text, and query text routinely contains identity data (issue #61 section 5).
    # The preamble would copy it into the trace on every debounced keystroke. Nothing in this function
    # logs the script, a fragment of it, or a parse message: the counts below are all that is ever
    # written, and only at DEBUG.

    process {
        try {
            $Parsed = Get-SqlScriptFragment -SqlText $SqlText -ParserVersion $ParserVersion

            if ($Parsed.Status -ne "Ok") {
                return [PSCustomObject]@{
                    Status        = "Unavailable"
                    Diagnostic    = @()
                    ParserVersion = $null
                }
            }

            $Diagnostic = @(ConvertTo-SqlSyntaxDiagnostic -ParseError $Parsed.ParseError -SqlText $SqlText -Source $Source)

            # Count only. The messages carry identifiers lifted straight out of the script
            # ("Incorrect syntax near 'Person'."), so they are never logged here at any level.
            "Parsed script with {0}: {1} syntax diagnostic(s)" -f $Parsed.ParserVersion, $Diagnostic.Count | Write-LogOutput -LogType DEBUG

            return [PSCustomObject]@{
                Status        = "Ok"
                Diagnostic    = $Diagnostic
                ParserVersion = $Parsed.ParserVersion
            }
        }
        catch {
            # A parser that throws must not be worse than a parser that is missing. The exception
            # message can quote the script, so it is not logged either.
            "The T-SQL parser failed while checking the query; syntax diagnostics are unavailable for this run." | Write-LogOutput -LogType DEBUG

            return [PSCustomObject]@{
                Status        = "Unavailable"
                Diagnostic    = @()
                ParserVersion = $null
            }
        }
    }
}

function ConvertTo-SqlSyntaxDiagnostic {
    <#
    .SYNOPSIS
        Maps ScriptDom parse errors onto the shared marker shape.

    .DESCRIPTION
        Kept separate from the parse so the same mapping serves both callers: Get-SqlSyntaxDiagnostic,
        which parses for itself, and Get-SqlDiagnostic, which parses once for all three passes. Two
        copies of this would be two chances for the syntax markers to land in different places
        depending on which entry point the application happened to use.

    .PARAMETER ParseError
        The errors ScriptDom reported.

    .PARAMETER SqlText
        The script they refer to, used only to widen each marker onto the offending token.

    .PARAMETER Source
        The pass label written to each diagnostic.

    .OUTPUTS
        Marker-shaped [PSCustomObject]s.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $ParseError,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $false)]
        [string]$Source = "T-SQL syntax"
    )

    # No tracer preamble: the parse messages quote the user's query (issue #61 section 5).

    return @(foreach ($ParseErrorItem in @($ParseError)) {
            if ($null -eq $ParseErrorItem) {
                continue
            }

            [PSCustomObject][Ordered]@{
                Line      = [int]$ParseErrorItem.Line
                Column    = [int]$ParseErrorItem.Column
                EndLine   = [int]$ParseErrorItem.Line
                EndColumn = Get-SqlDiagnosticEndColumn -SqlText $SqlText -Offset $ParseErrorItem.Offset -Column $ParseErrorItem.Column
                Severity  = "Error"
                Message   = [string]$ParseErrorItem.Message
                Source    = $Source
                Number    = [int]$ParseErrorItem.Number
            }
        })
}
