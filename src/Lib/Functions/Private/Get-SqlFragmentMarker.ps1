function Get-SqlFragmentMarker {
    <#
    .SYNOPSIS
        Converts a ScriptDom fragment into the line/column range a Monaco marker needs.

    .DESCRIPTION
        A fragment knows where it starts (StartLine, StartColumn) but not where it ends - only how
        many characters long it is. The end position is recovered from the token stream instead: the
        fragment's last token carries its own line and column, and its text gives the width.

        Both coordinate systems here are one-based and both are relative to the text that was parsed,
        which is the same convention ScriptDom uses for parse errors. That is what lets a schema or
        compatibility marker travel through Move-SqlDiagnosticToSelection unchanged when the user
        executed a selection rather than the whole script.

    .PARAMETER Fragment
        The node to place a marker on.

    .PARAMETER KeywordOnly
        Span the fragment's FIRST token instead of the whole fragment. Used by the execution-model
        rules of issue #61 section 3.4: underlining an entire UPDATE statement buries the point,
        whereas underlining the keyword says exactly what is not supported.

    .OUTPUTS
        [PSCustomObject] with Line, Column, EndLine and EndColumn, or $null when the fragment carries
        no usable position.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment,
        [Parameter(Mandatory = $false)]
        [switch]$KeywordOnly
    )

    # No tracer preamble: called per diagnostic, over the user's query (issue #61 section 5).

    if ($null -eq $Fragment) {
        return $null
    }

    $Line = [int]$Fragment.StartLine
    $Column = [int]$Fragment.StartColumn

    if ($Line -lt 1 -or $Column -lt 1) {
        return $null
    }

    $EndLine = $Line
    $EndColumn = $Column + 1

    try {
        $Token = $Fragment.ScriptTokenStream
        $TokenIndex = if ($KeywordOnly) { [int]$Fragment.FirstTokenIndex } else { [int]$Fragment.LastTokenIndex }

        if ($null -ne $Token -and $TokenIndex -ge 0 -and $TokenIndex -lt $Token.Count) {
            $Last = $Token[$TokenIndex]
            $Width = 1
            if (![string]::IsNullOrEmpty($Last.Text)) {
                $Width = $Last.Text.Length
            }

            $EndLine = [int]$Last.Line
            $EndColumn = [int]$Last.Column + $Width
        }
    }
    catch {
        # A marker that is one character wide is still on the right token. Failing to widen it must
        # never cost the diagnostic itself.
        $EndLine = $Line
        $EndColumn = $Column + 1
    }

    # A range that ends before it starts would be rejected by Monaco and the diagnostic would vanish.
    if ($EndLine -lt $Line -or ($EndLine -eq $Line -and $EndColumn -le $Column)) {
        $EndLine = $Line
        $EndColumn = $Column + 1
    }

    return [PSCustomObject][Ordered]@{
        Line      = $Line
        Column    = $Column
        EndLine   = $EndLine
        EndColumn = $EndColumn
    }
}
