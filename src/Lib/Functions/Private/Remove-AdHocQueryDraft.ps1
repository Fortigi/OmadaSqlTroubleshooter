function Remove-AdHocQueryDraft {
    <#
    .SYNOPSIS
        Forgets the ad-hoc query draft of one tab, or every draft.

    .DESCRIPTION
        Called when a draft no longer describes unsaved work: the query was saved to Omada, the tab now
        holds a saved query, the user emptied the editor, the user closed the tab and chose not to save,
        or the user declined to restore the drafts at start-up.

        A tab without a draft is not an error, and nothing is written in that case: this runs on every
        query selection, and rewriting an unchanged store each time would be wasted disk I/O.

        Never throws. It runs on the way to closing a tab and from the query selection handler, and a
        file that cannot be written must not stop either; the failure is a warning.

    .PARAMETER TabId
        The tab whose draft to forget.

    .PARAMETER All
        Forget every draft.

    .PARAMETER Path
        The draft store. Defaults to Get-AdHocQueryDraftPath.

    .OUTPUTS
        None.
    #>
    [CmdletBinding(DefaultParameterSetName = "Tab")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "Tab")]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$TabId,

        [Parameter(Mandatory = $true, ParameterSetName = "All")]
        [switch]$All,

        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-AdHocQueryDraftPath)
    )

    try {
        $Private:Existing = @(Get-AdHocQueryDraft -Path $Path)
        $Private:Kept = @($Private:Existing | Where-Object { -not $All -and $_.TabId -ne $TabId })

        if ($Private:Kept.Count -eq $Private:Existing.Count) {
            return
        }

        Write-AdHocQueryDraftStore -Path $Path -Draft $Private:Kept
    }
    catch {
        # Never in the way of what the user is doing: a draft that could not be forgotten is offered
        # once more at the next start, which costs one click.
        "Could not remove an ad-hoc query draft from '{0}': {1}" -f $Path, $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
    }
}
