function ConvertTo-SingleLineSqlText {
    <#
    .SYNOPSIS
        Puts a statement on one line, for the Results header and the text output.

    .DESCRIPTION
        Every line is trimmed, empty lines are dropped, and what remains is joined with a single
        space. A leading comment stays in front, so

            --Test query 1
            SELECT *
            FROM Test
            WHERE Id = 1

        becomes "--Test query 1 SELECT * FROM Test WHERE Id = 1". The result is for reading only and
        is never executed: on one line a "--" comment would comment out the rest.

        By default the result is capped at MaxLength characters and ends in an ellipsis. The grid
        header is cut off at the window edge by WPF anyway, and the cap keeps the tooltip that shows
        the whole line from growing to the size of a long script. The text output asks for -NoCap.

    .PARAMETER Text
        The statement text. Null and empty yield an empty string.

    .PARAMETER MaxLength
        The cap, ellipsis included. Defaults to 1024.

    .PARAMETER NoCap
        Return the whole line.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertTo-SingleLineSqlText -Text "--Test query 1`r`nSELECT *`r`nFROM Test"

    .NOTES
        No tracer preamble: the parameter is the user's query text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,
        [ValidateRange(2, [int]::MaxValue)]
        [int]$MaxLength = 1024,
        [switch]$NoCap
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $Line = foreach ($CurrentLine in ($Text -split "\r?\n|\r")) {
        $Trimmed = $CurrentLine.Trim()
        if ($Trimmed.Length -gt 0) {
            $Trimmed
        }
    }

    $SingleLine = @($Line) -join " "

    if (-not $NoCap -and $SingleLine.Length -gt $MaxLength) {
        return $SingleLine.Substring(0, $MaxLength - 1).TrimEnd() + [char]0x2026
    }

    return $SingleLine
}
