function Get-TabEditorText {
    <#
    .SYNOPSIS
        The text a tab's editor holds, or is about to hold.

    .DESCRIPTION
        EditorText is what Monaco last reported (Set-TabEditorText). A tab whose editor has not
        loaded yet - a duplicated tab, or one restored with an ad-hoc draft, closed before it was ever
        shown - has reported nothing, but its text is waiting in PendingEditorText to be pushed in.
        That text is just as unsaved, so it counts.

    .PARAMETER TabSession
        The tab.

    .OUTPUTS
        [string] The text, or $null when neither is known.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession
    )

    if ($null -eq $TabSession) {
        return $null
    }

    if ($null -ne $TabSession.EditorText) {
        return [string]$TabSession.EditorText
    }

    return $TabSession.PendingEditorText
}
