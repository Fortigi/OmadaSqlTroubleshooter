function Set-TabQueryClean {
    <#
    .SYNOPSIS
        Marks a tab as holding exactly what is saved, after its editor was loaded from the tenant.

    .DESCRIPTION
        The dirty flag says "the editor differs from the saved query", and the close prompts rely on
        it. It used to be cleared only by a save, so typing in a tab and then selecting a query left
        the freshly loaded query marked as changed, and closing asked to save a query nobody had
        touched. Set-EditorValue calls this once the loaded text has been pushed into the editor.

    .PARAMETER TabSession
        The tab. $null is ignored.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession
    )

    if ($null -eq $TabSession -or -not $TabSession.IsDirty) {
        return
    }

    $TabSession.IsDirty = $false
    Update-TabHeaderTitle -TabSession $TabSession
}
