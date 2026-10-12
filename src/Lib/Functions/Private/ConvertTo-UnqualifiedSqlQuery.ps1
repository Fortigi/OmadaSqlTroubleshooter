function ConvertTo-UnqualifiedSqlQuery {
    <#
    .SYNOPSIS
        Removes database prefixes and USE statements from a script, so what is posted to Omada is
        something SqlDataProducer can execute.

    .DESCRIPTION
        The write half of issue #152; Get-SqlDatabaseReference is the read half. The database has
        already been resolved to a data connection by the time this runs, so the prefix has done its
        job and must not reach the server: SqlDataProducer executes the text against the connection
        on the data object, where a three-part name is a SQL error, and USE is meaningless because
        the connection is already fixed (#152 criterion 6).

        The edits are made on ScriptDom's offsets rather than by a regular expression, for the same
        reason the scan is: the parser has already decided what is an identifier and what is text
        inside a string literal or a comment, so a prefix-looking run of characters in a literal is
        untouched (#152 criterion 15) without this function having to know anything about quoting.

        Each edit is a deletion of a half-open span, and the spans are applied in DESCENDING order so
        that removing one cannot move the offsets of the ones not yet applied.

        WHERE A PREFIX ENDS. For [Db].[Schema].[Table] the span runs from the name's start to the
        schema identifier, leaving [Schema].[Table]. The two-dot [Db]..[Table] form is the case worth
        naming: ScriptDom still reports a SchemaIdentifier there, but it is the EMPTY identifier
        between the two dots, so cutting to it would leave a leading ".Table". When the schema part
        is empty the span therefore runs to the base identifier instead, removing "[Db].." whole.

    .PARAMETER SqlText
        The script to rewrite. Null, empty and whitespace-only input are returned unchanged.

    .PARAMETER ParserVersion
        An explicit TSqlNNNParser to use. Omit to take the newest parser the loaded assembly ships.

    .OUTPUTS
        [string] the rewritten script, or the input unchanged when ScriptDom is unavailable or the
        script addresses no database at all.
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

    # DELIBERATELY no $Script:Tracer preamble and no logging of the text (issue #61 section 5).

    if ([string]::IsNullOrWhiteSpace($SqlText)) {
        return $SqlText
    }

    $Parsed = Get-SqlScriptFragment -SqlText $SqlText -ParserVersion $ParserVersion
    if ($Parsed.Status -ne "Ok" -or $null -eq $Parsed.Fragment) {
        return $SqlText
    }

    $Span = [System.Collections.Generic.List[object]]::new()

    foreach ($Object in @(Get-SqlFragmentDescendant -Fragment $Parsed.Fragment -TypeName "SchemaObjectName" -IncludeSelf)) {
        if ($null -eq $Object.DatabaseIdentifier -or [string]::IsNullOrEmpty($Object.DatabaseIdentifier.Value)) {
            continue
        }

        # See "WHERE A PREFIX ENDS" above: the empty schema identifier of the two-dot form must not
        # be the cut point, or the rewritten name keeps a leading dot.
        $End = $null
        if ($null -ne $Object.SchemaIdentifier -and ![string]::IsNullOrEmpty($Object.SchemaIdentifier.Value)) {
            $End = $Object.SchemaIdentifier.StartOffset
        }
        elseif ($null -ne $Object.BaseIdentifier) {
            $End = $Object.BaseIdentifier.StartOffset
        }

        if ($null -eq $End -or $End -le $Object.StartOffset) {
            continue
        }

        $Span.Add([PSCustomObject]@{ Start = $Object.StartOffset; End = $End })
    }

    foreach ($Use in @(Get-SqlFragmentDescendant -Fragment $Parsed.Fragment -TypeName "UseStatement" -IncludeSelf)) {
        if ($Use.FragmentLength -le 0) {
            continue
        }

        # The whole statement goes, its terminating semicolon included when ScriptDom counted it as
        # part of the fragment. Whatever separator is left behind is whitespace between statements.
        $Span.Add([PSCustomObject]@{ Start = $Use.StartOffset; End = $Use.StartOffset + $Use.FragmentLength })
    }

    if ($Span.Count -eq 0) {
        return $SqlText
    }

    $Rewritten = [System.Text.StringBuilder]::new($SqlText)
    foreach ($Item in @($Span | Sort-Object -Property Start -Descending)) {
        $Start = [Math]::Max(0, $Item.Start)
        $End = [Math]::Min($SqlText.Length, $Item.End)
        if ($End -gt $Start) {
            [void]$Rewritten.Remove($Start, $End - $Start)
        }
    }

    return $Rewritten.ToString()
}
