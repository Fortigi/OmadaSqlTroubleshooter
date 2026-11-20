function Set-AdHocQueryDraftOnTab {
    <#
    .SYNOPSIS
        Puts a kept ad-hoc query draft back into a tab.

    .DESCRIPTION
        The text goes in as PendingEditorText, the same channel a duplicated tab uses: the tab's
        NavigationCompleted handler (Initialize-WebViewForTab) pushes it into Monaco once the editor
        has loaded, after Set-EditorValue, so nothing loaded on the way can overwrite it. The Display
        name the draft was kept with is restored the same way, through PendingDisplayName.

        The tab is marked dirty, because the text is not saved anywhere but the draft store: closing
        the tab or the application asks about it again, and the draft is kept until it is saved or
        discarded.

    .PARAMETER TabSession
        The tab to restore into.

    .PARAMETER Draft
        The draft, from Get-AdHocQueryDraft.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession,

        [Parameter(Mandatory = $true)]
        $Draft
    )

    $TabSession.PendingEditorText = [string]$Draft.Text
    Set-TabEditorText -TabSession $TabSession -Text $Draft.Text
    $TabSession | Add-Member -NotePropertyName "DraftText" -NotePropertyValue ([string]$Draft.Text) -Force
    $TabSession.IsDirty = $true

    $Private:DisplayName = [string]$Draft.TabConfig.DisplayName
    if (![string]::IsNullOrWhiteSpace($Private:DisplayName)) {
        $TabSession.PendingDisplayName = $Private:DisplayName
        $TabSession.Elements.TextBoxDisplayName.Text = $Private:DisplayName
    }

    Update-TabHeaderTitle -TabSession $TabSession
}
