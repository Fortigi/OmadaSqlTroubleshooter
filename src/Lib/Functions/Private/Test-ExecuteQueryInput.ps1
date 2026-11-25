function Test-ExecuteQueryInput {
    <#
    .SYNOPSIS
        Whether Execute has something to run.

    .DESCRIPTION
        A selected saved query always has: the pipeline fetches it from the tenant, and the editor
        text is sent along with it. An ad-hoc query (no saved query selected, Test-AdHocQuery) has only
        what is in the editor, so an empty editor is refused before anything is sent - it would
        otherwise create the temporary query object just to have Omada reject an empty query.

        The editor text is the one Monaco last reported (Set-TabEditorText), read synchronously; the
        execute itself still reads the editor fresh.

    .PARAMETER QueryDoId
        The selected query's DoId, or $null.

    .PARAMETER EditorText
        What the editor holds.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $QueryDoId,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$EditorText
    )

    if (-not (Test-AdHocQuery -QueryDoId $QueryDoId)) {
        return $true
    }

    return -not [string]::IsNullOrWhiteSpace($EditorText)
}
