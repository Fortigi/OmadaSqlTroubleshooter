function Get-SqlSyntaxWarningMessage {
    <#
    .SYNOPSIS
        Builds the text of the "execute anyway?" confirmation shown when a query has syntax errors.

    .DESCRIPTION
        Deliberately says how many errors there are and where the first one is, and NOT what the
        parser said about it. Two reasons, in order of importance:

          * The message text is the one part of a diagnostic that quotes the script - "Incorrect
            syntax near 'Person'." - and issue #61 section 5 keeps script-derived identifiers out of
            anything that can be written down. The dialog text is passed to Open-ChoiceForm, which
            traces its bound parameters like every other function here.
          * It is redundant. The squiggle is already on the offending token in the editor, with the
            full message in its hover, which is where the user is looking.

        The wording is a question, never a refusal. The client parser and the tenant's actual
        compatibility level can legitimately disagree, so the user must always be able to overrule
        this (issue #61 acceptance criterion 4).

    .PARAMETER Diagnostic
        The syntax diagnostics found in the script.

    .OUTPUTS
        [string] the confirmation text, or $null when there is nothing to confirm.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Diagnostic
    )

    # No tracer preamble: the diagnostics carry identifiers taken from the user's query.

    $Item = @($Diagnostic | Where-Object { $null -ne $_ })
    if ($Item.Count -eq 0) {
        return $null
    }

    $First = $Item | Sort-Object -Property @{ Expression = { [int]$_.Line } }, @{ Expression = { [int]$_.Column } } | Select-Object -First 1

    if ($Item.Count -eq 1) {
        $Summary = "This query has 1 syntax error, at line {0}, column {1}." -f $First.Line, $First.Column
    }
    else {
        $Summary = "This query has {0} syntax errors. The first is at line {1}, column {2}." -f $Item.Count, $First.Line, $First.Column
    }

    return "{0}`r`n`r`nThe editor marks each one; hover a marker for the parser's message.`r`n`r`nThe check runs locally and can disagree with the server, so you can execute anyway.`r`n`r`nExecute the query?" -f $Summary
}
