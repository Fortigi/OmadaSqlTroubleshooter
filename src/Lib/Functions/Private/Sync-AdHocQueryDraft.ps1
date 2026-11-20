function Sync-AdHocQueryDraft {
    <#
    .SYNOPSIS
        Brings one tab's entry in the ad-hoc query draft store in line with the tab.

    .DESCRIPTION
        A tab has a draft exactly when closing it would offer to save its text as a new query
        (Resolve-QuerySavePrompt answering SaveNew): an ad-hoc query, changed since it was last loaded
        or saved, that is not empty. Anything else - a saved query is selected, the query was saved,
        the user emptied the editor - removes the draft.

        Connection state is deliberately not part of it. A disconnected tab cannot save, which is the
        strongest reason to keep its draft.

        The text kept is DraftText, the editor as of the last USER edit, not EditorText (see
        Set-TabEditorText). Disconnecting clears the editor programmatically; persisting EditorText
        would delete the very draft that makes that recoverable.

        A failure to write is a warning, not an error: this runs from the completion poll timer, where
        a modal error dialog every two seconds over a full disk would make the application unusable,
        and the work is still in the editor.

    .PARAMETER TabSession
        The tab to synchronise.

    .PARAMETER Path
        The draft store. Defaults to Get-AdHocQueryDraftPath.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession,

        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-AdHocQueryDraftPath)
    )

    if ($null -eq $TabSession -or [string]::IsNullOrWhiteSpace($TabSession.Id)) {
        return
    }

    $TabSession | Add-Member -NotePropertyName "DraftPending" -NotePropertyValue $false -Force

    try {
        $Private:Prompt = Resolve-QuerySavePrompt -QueryDoId $TabSession.AppConfig.CurrentSqlQuery.DoId -EditorText $TabSession.DraftText -IsDirty ([bool]$TabSession.IsDirty) -Connected $true

        if ($Private:Prompt -eq "SaveNew") {
            $Private:TabConfig = ConvertTo-AdHocQueryDraftTabConfig -TabId $TabSession.Id -AppConfig $TabSession.AppConfig -DisplayName $TabSession.Elements.TextBoxDisplayName.Text
            Save-AdHocQueryDraft -Path $Path -TabId $TabSession.Id -Text $TabSession.DraftText -TabConfig $Private:TabConfig
            return
        }

        Remove-AdHocQueryDraft -Path $Path -TabId $TabSession.Id
    }
    catch {
        "Could not update the ad-hoc query draft of tab '{0}': {1}" -f $TabSession.DisplayName, $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
    }
}
