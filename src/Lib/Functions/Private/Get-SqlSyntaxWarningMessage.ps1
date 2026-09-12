function Get-SqlSyntaxWarningMessage {
    <#
    .SYNOPSIS
        Builds the text of the "execute anyway?" confirmation shown when a query has diagnostics that
        take part in the execute-time check.

    .DESCRIPTION
        Deliberately says how many problems there are, what kind they are and where the first one is,
        and NOT what any of them said about the query. Two reasons, in order of importance:

          * A diagnostic's message is the one part of it that quotes the script - "Incorrect syntax
            near 'Person'.", or a compatibility rule naming the user's own alias - and issue #61
            section 5 and acceptance criterion A10 keep script-derived identifiers out of anything
            that can be written down. The dialog text is passed to Open-ChoiceForm, which traces its
            bound parameters like every other function here.
          * It is redundant. The squiggle is already on the offending token in the editor, with the
            full message in its hover, which is where the user is looking.

        The two kinds are counted separately because they are different claims and the user's answer
        may differ. A syntax error is SQL Server's own verdict on the batch. An Omada compatibility
        diagnostic is observed behaviour of the tenant - a statement the tool's read-only access
        cannot run, or a result set that will come back empty - which is version- and
        permission-dependent, and which the user may well know better than the rules do.

        The wording is a question, never a refusal. Nothing in this feature prevents anything; the
        user must always be able to overrule it (issue #61 acceptance criteria 4 and A7).

    .PARAMETER Diagnostic
        The diagnostics that take part in the check, as selected by Test-SqlDiagnosticBlocksExecution.

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

    $SyntaxCount = @($Item | Where-Object { [string]$_.Source -eq "T-SQL syntax" }).Count
    $OmadaCount = $Item.Count - $SyntaxCount

    $Part = [System.Collections.Generic.List[string]]::new()
    if ($SyntaxCount -eq 1) {
        $Part.Add("1 syntax error")
    }
    elseif ($SyntaxCount -gt 1) {
        $Part.Add("{0} syntax errors" -f $SyntaxCount)
    }

    if ($OmadaCount -eq 1) {
        $Part.Add("1 Omada compatibility problem")
    }
    elseif ($OmadaCount -gt 1) {
        $Part.Add("{0} Omada compatibility problems" -f $OmadaCount)
    }

    $Summary = "This query has {0}." -f ($Part -join " and ")

    if ($Item.Count -eq 1) {
        $Summary = "{0} It is at line {1}, column {2}." -f $Summary, $First.Line, $First.Column
    }
    else {
        $Summary = "{0} The first is at line {1}, column {2}." -f $Summary, $First.Line, $First.Column
    }

    return "{0}`r`n`r`nThe editor marks each one; hover a marker for the full message.`r`n`r`nThe check runs locally and can disagree with the server, so you can execute anyway.`r`n`r`nExecute the query?" -f $Summary
}
