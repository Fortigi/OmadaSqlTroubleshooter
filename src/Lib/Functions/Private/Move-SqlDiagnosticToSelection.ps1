function Move-SqlDiagnosticToSelection {
    <#
    .SYNOPSIS
        Rebases diagnostics parsed from a selection onto the full editor model.

    .DESCRIPTION
        "Execute selection" validates the text that will actually run, so the parser is handed the
        selection alone and reports positions relative to it: the first line of the selection is
        line 1. Monaco's markers are positioned against the whole model, so pushing those positions
        through unchanged puts the squiggle on the wrong line - by exactly the distance from the top
        of the document to the top of the selection.

        This shifts each diagnostic back onto the model. Only the first line takes a column shift:
        a selection can start mid-line, but every line after the first begins at column 1 in both
        coordinate systems.

        Validating the selection rather than the whole script is deliberate, not a shortcut - a
        syntax error somewhere else in the file must not block a selection that is itself valid - so
        the offset is corrected here rather than by parsing the full text.

    .PARAMETER Diagnostic
        The diagnostics as the parser reported them, relative to the selection.

    .PARAMETER StartLine
        One-based line in the model where the selection starts.

    .PARAMETER StartColumn
        One-based column in the model where the selection starts.

    .OUTPUTS
        The diagnostics with model-relative positions. Order and every other field are preserved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Diagnostic,
        [Parameter(Mandatory = $true)]
        [int]$StartLine,
        [Parameter(Mandatory = $true)]
        [int]$StartColumn
    )

    # No tracer preamble: the diagnostics carry identifiers taken from the user's query (issue #61 section 5).

    $LineShift = $StartLine - 1
    $ColumnShift = $StartColumn - 1

    # Nothing to do for a selection that starts at the top left, which is also what a caller with no
    # selection passes. Returning early keeps that case free of pointless object churn.
    if ($LineShift -eq 0 -and $ColumnShift -eq 0) {
        return @($Diagnostic | Where-Object { $null -ne $_ })
    }

    $Moved = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Item in @($Diagnostic)) {
        if ($null -eq $Item) {
            continue
        }

        $Line = [int]$Item.Line
        $EndLine = [int]$Item.EndLine

        # Copied and adjusted rather than rebuilt from a fixed set of properties. Get-SqlSyntaxDiagnostic
        # also emits Number, and the schema pass will add fields of its own; listing the fields here
        # would silently drop them, and would do it only for an executed selection, so the diagnostic
        # shape would depend on how the query was run.
        $Copy = $Item.PSObject.Copy()

        $Copy.Line = $Line + $LineShift
        $Copy.EndLine = $EndLine + $LineShift

        # Only the first line takes a column shift: a selection can start mid-line, but every line
        # after it begins at column 1 in the model as well as in the selection.
        if ($Line -eq 1) {
            $Copy.Column = [int]$Item.Column + $ColumnShift
        }

        if ($EndLine -eq 1) {
            $Copy.EndColumn = [int]$Item.EndColumn + $ColumnShift
        }

        $Moved.Add($Copy)
    }

    return @($Moved)
}
