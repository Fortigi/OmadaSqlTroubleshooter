function Get-SqlScriptFragment {
    <#
    .SYNOPSIS
        Parses a T-SQL script with ScriptDom once and hands back both the parse errors and the
        syntax tree.

    .DESCRIPTION
        All three validation passes of issue #61 read the same tree: the syntax pass maps the parse
        errors, the schema pass resolves identifiers out of the AST, and the Omada compatibility pass
        runs its rule predicates over it. Parsing three times per debounced keystroke would be three
        times the work for one answer, so the parse lives here and every pass is handed the result.

        The return shape mirrors Get-SqlSyntaxDiagnostic's, for the same reason: "nothing to report"
        and "could not look" are different answers.

            Status         Ok          the script was parsed; Fragment and ParseError are populated
                           Unavailable ScriptDom is not loaded, so nothing was parsed
            Fragment       the TSqlScript root, or $null
            ParseError     the parse errors ScriptDom reported; empty for a clean script
            ParserVersion  the TSqlNNNParser actually used, or $null

        Unavailable is a return value, never an exception (issue #61 acceptance criterion 6).

        A script that does not parse still yields a Fragment: ScriptDom recovers, and a partial tree
        lets the later passes say something useful about the statements it did understand. Callers
        that need a trustworthy tree check ParseError themselves.

    .PARAMETER SqlText
        The script to parse. Null, empty and whitespace-only input are valid and yield Status Ok with
        Fragment $null - there is nothing to inspect, which is not the same as a parser that could not
        look. Every caller already treats a null Fragment as "nothing to say about this script".

    .PARAMETER ParserVersion
        An explicit TSqlNNNParser to use. Omit to take the newest parser the loaded assembly ships.

    .OUTPUTS
        [PSCustomObject] with Status, Fragment, ParseError and ParserVersion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ParserVersion
    )

    # DELIBERATELY no $Script:Tracer preamble. $PSBoundParameters IS the user's query text here, and
    # the preamble would copy it into the trace on every debounced keystroke (issue #61 section 5).

    try {
        $ParserType = Get-SqlParserType -ParserVersion $ParserVersion

        if ($null -eq $ParserType) {
            return [PSCustomObject]@{
                Status        = "Unavailable"
                Fragment      = $null
                ParseError    = @()
                ParserVersion = $null
            }
        }

        if ([string]::IsNullOrWhiteSpace($SqlText)) {
            return [PSCustomObject]@{
                Status        = "Ok"
                Fragment      = $null
                ParseError    = @()
                ParserVersion = $ParserType.Name
            }
        }

        # initialQuotedIdentifiers: $true matches the SET QUOTED_IDENTIFIER ON that .NET clients -
        # Omada's included - connect under. It decides what "..." means: a delimited identifier under
        # ON, a string literal under OFF. The schema pass reads identifiers out of this tree, so the
        # setting has to be the tenant's.
        $Parser = $ParserType::new($true)

        $ParseError = $null
        $Reader = [System.IO.StringReader]::new($SqlText)
        try {
            $Fragment = $Parser.Parse($Reader, [ref]$ParseError)
        }
        finally {
            $Reader.Dispose()
        }

        return [PSCustomObject]@{
            Status        = "Ok"
            Fragment      = $Fragment
            ParseError    = @(@($ParseError) | Where-Object { $null -ne $_ })
            ParserVersion = $ParserType.Name
        }
    }
    catch {
        # A parser that throws must not be worse than a parser that is missing. The exception message
        # can quote the script, so it is not logged.
        "The T-SQL parser failed while reading the query; client-side diagnostics are unavailable for this run." | Write-LogOutput -LogType DEBUG

        return [PSCustomObject]@{
            Status        = "Unavailable"
            Fragment      = $null
            ParseError    = @()
            ParserVersion = $null
        }
    }
}
