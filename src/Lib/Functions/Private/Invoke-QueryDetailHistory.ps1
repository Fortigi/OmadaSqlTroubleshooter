function Invoke-QueryDetailHistory {
    <#
    .SYNOPSIS
        Opens the history window for the query details' query, on top of the details, and reads the
        details again afterwards.

    .DESCRIPTION
        From Compare / restore, the window selects the newest version. From a double-clicked row of the
        History tab (-Entry), it selects the version of that change (Find-SqlHistoryItemIndex); a
        change that did not touch the SQL - a rename - has no version there, and the newest is
        selected instead, with a note in the log.

        The query's UId is handed over for the window's Details tab, so it is not read again.

        A version restored there opened its tab and asked the query manager to close
        (Complete-QueryManagerChildWindow), in which case the details close too.

    .PARAMETER Entry
        The History tab's row (ConvertTo-QueryHistoryEntry: When, Who, What, Fields).

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Entry
    )

    $Private:Query = $Script:QueryDetailForm.Query
    $Private:Arguments = @{
        DoId      = $Private:Query.DoId
        QueryName = $Private:Query.DisplayName
        Owner     = $Script:QueryDetailForm.Definition
        QueryUId  = [string]$Private:Query.UId
    }
    if ($null -ne $Entry) {
        $Private:Arguments.SelectChangeDate = $Entry.When
        $Private:Arguments.SelectChangedBy = [string]$Entry.Who
        "Opening the history at the change of {0} by {1} ({2})." -f $Entry.When, $Entry.Who, $Entry.What | Write-LogOutput -LogType DEBUG
    }

    Open-SqlHistoryForm @Private:Arguments

    if (-not (Complete-QueryManagerChildWindow -Window $Script:QueryDetailForm.Definition)) {
        Update-QueryDetailForm
    }
}

function Invoke-QueryDetailHistoryRow {
    <#
    .SYNOPSIS
        A double-click on the query details' History tab: the history window, at the version of the
        row the selection is in. Nothing for a selection over several rows, or none.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Rows = @(Get-DataGridSelectedRow -Grid $Script:QueryDetailForm.Elements.DataGridQueryHistory)
    if ($Private:Rows.Count -eq 1) {
        Invoke-QueryDetailHistory -Entry $Private:Rows[0]
    }
}
