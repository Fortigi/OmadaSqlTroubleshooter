function Resolve-QuerySavePrompt {
    <#
    .SYNOPSIS
        Decides whether closing a tab (or the application) has to offer to save its query, and how.

    .DESCRIPTION
        One decision for both places that close a query: a single tab (Close-TabSession) and the whole
        application (Confirm-UnsavedQueryOnClose, from the main window's Closing handler). Kept pure
        so the rules are tested rather than discovered on a tenant:

          - Nothing to offer when nothing changed since the last save or load.
          - Nothing to offer when the editor is empty. Saving an empty selected query would blank the
            stored object, and an empty ad-hoc query has nothing worth keeping.
          - "SaveExisting" for a selected query with unsaved changes.
          - "SaveNew" for an ad-hoc query with unsaved text: saving it creates a query object, so the
            caller has to ask for a name.
          - "Unavailable" when there is something to save but the tab is not connected. Saving needs a
            session with the tenant; the caller can only tell the user, and an ad-hoc query is still
            kept in the draft cache (Sync-AdHocQueryDraft).

    .PARAMETER QueryDoId
        The selected query's DoId, or $null for an ad-hoc query.

    .PARAMETER EditorText
        What the editor holds. $null when it is not known, which is treated as empty: there is
        nothing that could be saved.

    .PARAMETER IsDirty
        Whether the editor changed since the query was last loaded or saved.

    .PARAMETER Connected
        Whether the tab has a session with the tenant.

    .OUTPUTS
        [string] None, SaveExisting, SaveNew or Unavailable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $QueryDoId,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$EditorText,

        [bool]$IsDirty,

        [bool]$Connected
    )

    if (-not $IsDirty -or [string]::IsNullOrWhiteSpace($EditorText)) {
        return "None"
    }

    if (-not $Connected) {
        return "Unavailable"
    }

    if (Test-AdHocQuery -QueryDoId $QueryDoId) {
        return "SaveNew"
    }

    return "SaveExisting"
}
