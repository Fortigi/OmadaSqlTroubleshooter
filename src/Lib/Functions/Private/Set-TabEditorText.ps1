function Set-TabEditorText {
    <#
    .SYNOPSIS
        Records what a tab's editor holds, as Monaco last reported it.

    .DESCRIPTION
        The host cannot read the editor synchronously: every read is an ExecuteScriptAsync round-trip
        whose result arrives on a later dispatcher pass. Two things need the text at a moment when no
        such round-trip can be awaited - the main window's Closing handler, deciding whether to offer a
        save, and the ad-hoc draft cache, which must already be on disk when the process dies - so
        Monaco posts its text with every change (index.html, postEditorText) and it is kept here.

        Two copies are kept, and the difference matters:

          EditorText  what is on screen now, from every change. The close prompts read this.
          DraftText   the text as of the last USER edit. Sync-AdHocQueryDraft persists this. A
                      programmatic load - disconnecting clears the editor, selecting a query replaces
                      it - updates EditorText only, so it can never overwrite or delete a draft the
                      user wrote: the cache exists precisely for the case where the screen lost it.

        The properties are added when a tab object does not have them yet, so a tab built by an older
        code path (or a test double) is handled rather than throwing on assignment.

    .PARAMETER TabSession
        The tab whose editor reported.

    .PARAMETER Text
        The editor's full text.

    .PARAMETER UserEdit
        The text came from a user edit rather than a programmatic load.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,

        [switch]$UserEdit
    )

    if ($null -eq $TabSession) {
        return
    }

    $TabSession | Add-Member -NotePropertyName "EditorText" -NotePropertyValue $Text -Force

    if ($UserEdit) {
        $TabSession | Add-Member -NotePropertyName "DraftText" -NotePropertyValue $Text -Force
        $TabSession | Add-Member -NotePropertyName "DraftPending" -NotePropertyValue $true -Force
    }
}
