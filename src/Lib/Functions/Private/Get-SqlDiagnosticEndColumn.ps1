function Get-SqlDiagnosticEndColumn {
    <#
    .SYNOPSIS
        Works out where a diagnostic's squiggle should end.

    .DESCRIPTION
        ScriptDom reports a parse error as a single point - Line, Column and a character Offset into
        the script - with no extent. Monaco needs a range, and a range of exactly one character is a
        squiggle so short it is easy to miss on the token it is pointing at.

        This widens the point to the end of the token that starts there: a run of word characters, or
        a single character for punctuation and operators. Purely presentational; the position the
        parser reported is never moved.

    .PARAMETER SqlText
        The script the offset refers to.

    .PARAMETER Offset
        Zero-based character offset of the error, as ScriptDom reports it.

    .PARAMETER Column
        One-based column of the error, as ScriptDom reports it.

    .OUTPUTS
        [int] the one-based, exclusive end column, always greater than $Column.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $true)]
        [int]$Offset,
        [Parameter(Mandatory = $true)]
        [int]$Column
    )

    # No tracer preamble: called per diagnostic, and $SqlText is the user's query (issue #61 section 5).

    if ([string]::IsNullOrEmpty($SqlText) -or $Offset -lt 0 -or $Offset -ge $SqlText.Length) {
        return $Column + 1
    }

    $Index = $Offset
    while ($Index -lt $SqlText.Length -and ($SqlText[$Index] -match '[\w@#\$]')) {
        $Index++
    }

    $Length = $Index - $Offset
    if ($Length -lt 1) {
        $Length = 1
    }

    return $Column + $Length
}
