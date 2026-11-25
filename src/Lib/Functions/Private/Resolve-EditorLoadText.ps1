function Resolve-EditorLoadText {
    <#
    .SYNOPSIS
        Which text Set-EditorValue puts in the editor when it loads a saved query: the saved text, or
        an older version waiting to be restored.

    .DESCRIPTION
        Restoring a version from the history of a query that is not open opens it in a new tab
        (Open-SqlQueryInTab -RestoreText). That tab loads the saved text as soon as its editor is
        ready, which would overwrite anything pushed in earlier, so the restored text waits on the tab
        as PendingRestoreText and replaces the saved text at that load instead. It is taken once:
        later loads show the saved text again.

        Only called once the editor can take the text (Set-EditorValue checks the WebView first), so
        the waiting text is never used up by a load that could not reach the editor.

    .PARAMETER TabSession
        The tab being loaded.

    .PARAMETER SavedText
        The query's saved text.

    .OUTPUTS
        [PSCustomObject] @{ Text; Restored }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $TabSession,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SavedText
    )

    # A tab that never had a version waiting has no such property; that reads as nothing waiting.
    $Private:Pending = $null
    if ($null -ne $TabSession) {
        $Private:Pending = $TabSession.PSObject.Properties["PendingRestoreText"].Value
    }

    if ($null -eq $Private:Pending) {
        return [PSCustomObject]@{ Text = $SavedText; Restored = $false }
    }

    $TabSession.PendingRestoreText = $null
    return [PSCustomObject]@{ Text = [string]$Private:Pending; Restored = $true }
}
