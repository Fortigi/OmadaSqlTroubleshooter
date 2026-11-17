function Get-SqlScriptStatement {
    <#
    .SYNOPSIS
        Splits the T-SQL about to be executed into one entry per statement, so each statement can be
        run as its own query.

    .DESCRIPTION
        Issue #151. Execute used to run the editor contents as ONE query, so a script holding several
        statements could not be run at all: the user selected one statement, executed, read the grid,
        selected the next, and lost the previous result every time. This is the split that turns that
        script into one query - and therefore one result grid - per statement.

        The parse is not a new one. Get-SqlScriptFragment already parses this exact text for the three
        validation passes of issue #61 and hands back the TSqlScript root, so the split is a walk over
        Batches[].Statements[]. Descending through the batches matters: GO is a batch separator rather
        than a statement terminator, so a script with a GO in it has its statements spread across
        several batches.

        Each statement's text is CUT FROM THE ORIGINAL SOURCE by the fragment's StartOffset and
        FragmentLength, rather than rebuilt from the tree. The text is what gets written to the
        temporary query object and executed, so it has to be the user's own SQL - their formatting,
        their inline comments, their casing. A statement regenerated from the syntax tree would be
        equivalent SQL that the user never wrote, and the first thing they would notice is their
        comments missing from a query they are trying to debug.

        Splitting on ";" with a regular expression is the obvious cheap alternative and it is wrong on
        the first semicolon inside a string literal or a comment - it would turn one correct query into
        two invalid fragments and report two failures for it. ScriptDom is already loaded and already
        parses this text, so the correct split costs nothing extra.

        FALLING BACK TO ONE STATEMENT is a feature, not an error path. Whenever the split cannot be
        trusted, this returns a single entry carrying the original text, which is exactly what the
        application did before this issue - so the query still runs, the way it always has. That
        covers:

            - ScriptDom is not loaded (Status "Unavailable"), so nothing was parsed
            - the parser reported errors, so the tree may not describe what the user wrote
            - there is no tree at all (null, empty or whitespace-only text)
            - the tree holds no statements (a script of nothing but comments)

        The last one is worth stating: returning an empty list there would execute NOTHING, where today
        the text is sent and the tenant answers. Swallowing a run silently is worse than running a
        script that produces no rows.

    .PARAMETER SqlText
        The script to split. This is the text that will actually run - the selection when the user has
        one, the whole editor otherwise. Null, empty and whitespace-only are valid and yield a single
        statement carrying that same text.

    .PARAMETER ParserVersion
        An explicit TSqlNNNParser to use, passed straight through. Omit to take the newest parser the
        loaded assembly ships.

    .OUTPUTS
        An ordered array of [PSCustomObject] with:
            Ordinal      1-based position in editor order; what the Results header and the Messages
                         summary label the statement with
            Text         the statement's own source text
            StartOffset  where it starts in $SqlText
            Length       how long it is
            DisplayText  the statement's source text including the comment lines directly above
                         it; what the Results header and the text output show. Never executed
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

    # DELIBERATELY no $Script:Tracer preamble, for the reason Get-SqlScriptFragment records: the
    # parameter IS the user's query text, and the preamble would copy it into the trace.

    # The one-statement answer, built once. Every fallback below returns exactly this, so "we could not
    # split it safely" has a single definition and cannot drift between the four ways of reaching it.
    $Fallback = @(
        [PSCustomObject][Ordered]@{
            Ordinal     = 1
            Text        = $SqlText
            StartOffset = 0
            Length      = if ($null -eq $SqlText) { 0 } else { $SqlText.Length }
            DisplayText = $SqlText
        }
    )

    try {
        if ([string]::IsNullOrWhiteSpace($SqlText)) {
            return $Fallback
        }

        $Parse = Get-SqlScriptFragment -SqlText $SqlText -ParserVersion $ParserVersion

        # Three separate reasons to leave the text alone, kept separate on purpose. "Unavailable" means
        # nothing was parsed; a non-empty ParseError means the tree describes something other than what
        # the user wrote - Get-SqlScriptFragment returns a recovered partial tree in that case, which
        # is useful for putting squiggles on screen but must not be used to decide where to CUT
        # somebody's SQL.
        if ($Parse.Status -ne "Ok" -or @($Parse.ParseError).Count -gt 0 -or $null -eq $Parse.Fragment) {
            return $Fallback
        }

        $Statement = [System.Collections.Generic.List[object]]::new()
        $Ordinal = 0

        foreach ($Batch in @($Parse.Fragment.Batches)) {
            foreach ($Fragment in @($Batch.Statements)) {
                if ($null -eq $Fragment) {
                    continue
                }

                $StartOffset = [int]$Fragment.StartOffset
                $Length = [int]$Fragment.FragmentLength

                # A fragment that cannot be cut is skipped rather than guessed at. Substring on a bad
                # range throws, and a statement silently truncated to a shorter one would be sent to
                # the tenant as valid SQL that the user never wrote.
                if ($StartOffset -lt 0 -or $Length -le 0 -or ($StartOffset + $Length) -gt $SqlText.Length) {
                    continue
                }

                $Ordinal++
                $DisplayOffset = Get-SqlStatementLeadingCommentOffset -Fragment $Fragment
                $Statement.Add([PSCustomObject][Ordered]@{
                        Ordinal     = $Ordinal
                        Text        = $SqlText.Substring($StartOffset, $Length)
                        StartOffset = $StartOffset
                        Length      = $Length
                        # What the Results header and the text output show for this statement: the
                        # statement as the user wrote it, WITH the comment lines directly above it. A
                        # fragment starts at its first real token, so Text never carries that comment,
                        # and the comment is usually how the user names the query they are looking for.
                        DisplayText = $SqlText.Substring($DisplayOffset, ($StartOffset + $Length) - $DisplayOffset)
                    })
            }
        }

        # Nothing to run - a script of only comments, or one whose every fragment was unusable. The
        # text goes out as one query rather than as none.
        if ($Statement.Count -eq 0) {
            return $Fallback
        }

        return $Statement.ToArray()
    }
    catch {
        # A split that throws must never be worse than no split at all. The message can quote the
        # script, so it is not logged.
        "Splitting the query into statements failed; it will be executed as a single statement." | Write-LogOutput -LogType DEBUG

        return $Fallback
    }
}

function Get-SqlStatementLeadingCommentOffset {
    <#
    .SYNOPSIS
        The offset where a statement's leading comment starts, or the statement's own start offset
        when no comment sits directly above it.

    .DESCRIPTION
        Walks the script's token stream back from the statement's first token over whitespace and
        comments. The walk stops at the first significant token: the previous statement, its
        semicolon, or a GO. A comment is never taken across one of those.

        A comment on the same line as the previous statement belongs to that statement
        ("SELECT 1 -- the ones"), so it is skipped. Only a comment that starts after a line break
        counts as leading. A single-line comment always runs to the end of its line, so the next
        comment after it starts on a new line.

    .PARAMETER Fragment
        The statement fragment, which carries the whole script's ScriptTokenStream.

    .OUTPUTS
        [int] an offset into the parsed script text.

    .NOTES
        No tracer preamble: called once per statement, and the fragment carries the user's query text.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        $Fragment
    )

    $StartOffset = [int]$Fragment.StartOffset
    $Token = $Fragment.ScriptTokenStream
    $FirstTokenIndex = [int]$Fragment.FirstTokenIndex

    if ($null -eq $Token -or $FirstTokenIndex -le 0 -or $FirstTokenIndex -gt $Token.Count) {
        return $StartOffset
    }

    $Trivia = @("WhiteSpace", "SingleLineComment", "MultilineComment")

    $Index = $FirstTokenIndex - 1
    while ($Index -ge 0 -and [string]$Token[$Index].TokenType -in $Trivia) {
        $Index--
    }

    # Nothing significant in front of the statement: the start of the script counts as a line break.
    $SeenLineBreak = $Index -lt 0

    for ($Position = $Index + 1; $Position -lt $FirstTokenIndex; $Position++) {
        $Current = $Token[$Position]
        $TokenType = [string]$Current.TokenType
        $TokenText = [string]$Current.Text

        if ($TokenType -eq "WhiteSpace") {
            if ($TokenText.Contains("`n")) {
                $SeenLineBreak = $true
            }

            continue
        }

        if ($SeenLineBreak) {
            return [int]$Current.Offset
        }

        # A trailing comment of the previous statement. Whatever follows it is on a new line when it
        # is a single-line comment, or when the comment itself spans lines.
        if ($TokenType -eq "SingleLineComment" -or $TokenText.Contains("`n")) {
            $SeenLineBreak = $true
        }
    }

    return $StartOffset
}
