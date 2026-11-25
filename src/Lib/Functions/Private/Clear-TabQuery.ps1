function Clear-TabQuery {
    <#
    .SYNOPSIS
        New: clears the active tab's editor for a new, ad-hoc query.

    .DESCRIPTION
        Unsaved work is offered to be saved first - the same Save / Don't save / Cancel question as
        closing the tab (Resolve-QuerySavePrompt, Request-TabQuerySave), and an empty editor is not
        asked about. Cancel leaves everything as it was.

        Then the tab is detached from its saved query, the editor is emptied, and the tab is clean,
        named Query{#} again, with no ad-hoc draft. New creates nothing on the tenant: the query is
        created on its first Save (or Save as), when a name is asked for.

        Replaces the previous New, which saved the editor under the Display name. That one disabled
        the New button before saving and never enabled it again when the name already existed, so
        after one clash no new query could be created at all. Nothing here disables a button.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Tab = Get-ActiveTabSession
    if ($null -eq $Private:Tab) {
        return
    }

    $Private:Kind = Resolve-QuerySavePrompt -QueryDoId $Script:AppConfig.CurrentSqlQuery.DoId -EditorText (Get-TabEditorText -TabSession $Private:Tab) -IsDirty ([bool]$Private:Tab.IsDirty) -Connected ([bool]$Script:ConnectionStatus)
    if ($Private:Kind -ne "None" -and (Request-TabQuerySave -TabSession $Private:Tab -Kind $Private:Kind -NewQuery) -eq "Cancel") {
        "New query cancelled at the save prompt." | Write-LogOutput -LogType DEBUG
        return
    }

    $Private:Tab.IsDirty = $false
    $Private:Tab | Add-Member -NotePropertyName "DraftText" -NotePropertyValue $null -Force
    $Private:Tab | Add-Member -NotePropertyName "ProposedQueryName" -NotePropertyValue $null -Force

    Clear-TabSavedQuerySelection -TabSession $Private:Tab

    Push-ToEditor -ScriptToExecute "window.setEditorValue('');"
    Set-TabEditorText -TabSession $Private:Tab -Text ""

    Remove-AdHocQueryDraft -TabId $Private:Tab.Id
    Update-SavedQueryCommandState
    Update-TabHeaderTitle -TabSession $Private:Tab

    "New query: the editor was cleared." | Write-LogOutput -LogType DEBUG
}
