# The two indices of the Results/Messages tab control beside the query output. Selection is driven
# by index rather than by a named TabItem on purpose: Initialize-FormObject discovers elements by
# type and TabItem is not in its list, so a named tab item would never reach $TabSession.Elements.
$Script:QueryOutputResultsIndex = 0
$Script:QueryOutputMessagesIndex = 1

function Clear-TabMessage {
    <#
    .SYNOPSIS
    Empty a tab's Messages pane at the start of an execute.

    .DESCRIPTION
    Messages accumulate within one execute and are cleared when the next one starts (issue #93), so
    what the pane shows always describes the run the user just asked for rather than a mixture of
    that run and whatever preceded it.

    Selection returns to Results at the same time. Without that, a tab left on Messages by a previous
    failure would keep the user staring at the pane while their new query produced rows they could
    not see.

    .PARAMETER TabSession
    The tab whose pane to clear. Defaults to the active tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target) {
            return
        }

        if ($null -eq $Private:Target.QueryMessages) {
            $Private:Target.QueryMessages = [System.Collections.Generic.List[string]]::new()
        }
        else {
            $Private:Target.QueryMessages.Clear()
        }

        if ($null -ne $Private:Target.Elements) {
            if ($null -ne $Private:Target.Elements.TextBoxQueryMessages) {
                $Private:Target.Elements.TextBoxQueryMessages.Text = ""
            }

            if ($null -ne $Private:Target.Elements.TabControlQueryOutput) {
                $Private:Target.Elements.TabControlQueryOutput.SelectedIndex = $Script:QueryOutputResultsIndex
            }
        }
    }
    catch {
        "Could not clear the Messages pane: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Add-TabMessage {
    <#
    .SYNOPSIS
    Append a line to a tab's Messages pane, and optionally bring the pane to the front.

    .DESCRIPTION
    The Messages pane is what replaced the modal dialog for query failures (issue #93). A modal
    stopped the user, had to be dismissed before they could look at the query that caused it, and was
    gone once dismissed - so comparing an error against the SQL that produced it meant re-running the
    query. Here the text sits beside the editor for as long as it is useful, and is selectable and
    copyable because the pane is a read-only TextBox rather than a label.

    The list on the tab session is the source of truth and the TextBox is a rendering of it. Two tabs
    failing at the same time therefore cannot mix their output: neither list is reachable from the
    other tab, whatever Set-ActiveTabContext is pointing at when the second failure lands.

    .PARAMETER TabSession
    The tab the message belongs to. Defaults to the active tab, which during a background completion
    is the tab the work belongs to.

    .PARAMETER Text
    The line to append.

    .PARAMETER Focus
    Bring the Messages pane to the front. Set for failures and not for successes: a failure the user
    cannot see is the thing this issue set out to fix, while a successful query should still land
    them on their data.
    #>
    [CmdLetBinding()]
    param(
        $TabSession,
        [string]$Text,
        [switch]$Focus
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target) {
            return
        }

        if ($null -eq $Private:Target.QueryMessages) {
            $Private:Target.QueryMessages = [System.Collections.Generic.List[string]]::new()
        }

        $Private:Target.QueryMessages.Add($Text)

        if ($null -eq $Private:Target.Elements) {
            return
        }

        if ($null -ne $Private:Target.Elements.TextBoxQueryMessages) {
            $Private:Target.Elements.TextBoxQueryMessages.Text = ($Private:Target.QueryMessages -join "`r`n")
        }

        if ($Focus -and $null -ne $Private:Target.Elements.TabControlQueryOutput) {
            $Private:Target.Elements.TabControlQueryOutput.SelectedIndex = $Script:QueryOutputMessagesIndex
        }
    }
    catch {
        # This is a path that reports failures; it has nowhere useful to report its own.
        "Could not write to the Messages pane: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Write-TabExecuteSummary {
    <#
    .SYNOPSIS
    Record the rows read and the completion time for an execute, whether it succeeded or failed.

    .DESCRIPTION
    Issue #93 asks for both numbers on EVERY execute, not only successful ones, and that is what
    resolves the ambiguity issue #44 describes: an empty result and a failed query look identical
    today because neither shows rows. A pane that says "Rows read: 0" after a run that completed is
    telling the user something a blank grid cannot.

    Neither value is computed here. Format-ElapsedTime (issue #88) already renders the time and the
    row count already reaches the status bar; this is about putting them somewhere that survives the
    next thing the user does.

    .PARAMETER TabSession
    The tab the execute belongs to. Defaults to the active tab.

    .PARAMETER RowsRead
    The number of rows the query returned. Zero on a failure that never got as far as rows.

    .PARAMETER Elapsed
    The completion time, already formatted.
    #>
    [CmdLetBinding()]
    param(
        $TabSession,
        [int]$RowsRead = 0,
        [string]$Elapsed
    )

    Add-TabMessage -TabSession $TabSession -Text ("Rows read: {0:n0}" -f $RowsRead)
    Add-TabMessage -TabSession $TabSession -Text ("Completion time: {0}" -f $Elapsed)
}
