function Get-SqlSyntaxDiagnostic {
    <#
    .SYNOPSIS
        Parses a T-SQL script with ScriptDom and returns the parse errors as editor diagnostics.

    .DESCRIPTION
        The first of the two validation passes described in issue #61. Everything here is local:
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

    .PARAMETER SqlText
        The script to parse. Null, empty and whitespace-only input are valid and yield no
        diagnostics - an empty editor is not a syntax error.

    .PARAMETER ParserVersion
        An explicit TSqlNNNParser to use. Omit to take the newest parser the loaded assembly ships.

    .PARAMETER Source
        The value written to each diagnostic's Source field, which the editor shows next to the
        message and which distinguishes this pass from the schema pass that will share the same
        diagnostics channel.

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
            $ParserType = Get-SqlParserType -ParserVersion $ParserVersion

            if ($null -eq $ParserType) {
                return [PSCustomObject]@{
                    Status        = "Unavailable"
                    Diagnostic    = @()
                    ParserVersion = $null
                }
            }

            if ([string]::IsNullOrWhiteSpace($SqlText)) {
                return [PSCustomObject]@{
                    Status        = "Ok"
                    Diagnostic    = @()
                    ParserVersion = $ParserType.Name
                }
            }

            # initialQuotedIdentifiers: $true matches the SET QUOTED_IDENTIFIER ON that SQL Server
            # connections from .NET clients - Omada's included - run under. Parsing with it off would
            # reject "..." string literals that the tenant accepts.
            $Parser = $ParserType::new($true)

            $ParseError = $null
            $Reader = [System.IO.StringReader]::new($SqlText)
            try {
                [void]$Parser.Parse($Reader, [ref]$ParseError)
            }
            finally {
                $Reader.Dispose()
            }

            $Diagnostic = @(foreach ($ParseErrorItem in @($ParseError)) {
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

            # Count only. The messages carry identifiers lifted straight out of the script
            # ("Incorrect syntax near 'Person'."), so they are never logged here at any level.
            "Parsed script with {0}: {1} syntax diagnostic(s)" -f $ParserType.Name, $Diagnostic.Count | Write-LogOutput -LogType DEBUG

            return [PSCustomObject]@{
                Status        = "Ok"
                Diagnostic    = $Diagnostic
                ParserVersion = $ParserType.Name
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
