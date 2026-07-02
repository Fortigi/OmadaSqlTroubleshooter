function Show-QueryResultGridView {
    <#
    .SYNOPSIS
        Shows a set of query result rows in an Out-GridView popup.

    .DESCRIPTION
        Applies the same JSON round-trip sanitization used elsewhere (Omada can return invalid JSON keys) and
        opens the rows in Out-GridView with the given title. Used both for viewing the full query result and
        for viewing only the currently selected DataGrid cells.

    .PARAMETER Rows
        The row objects to display.

    .PARAMETER Title
        The window title for the Out-GridView popup.

    .EXAMPLE
        Show-QueryResultGridView -Rows $Script:RunTimeData.QueryResult.d.rows -Title "My Query"

    .NOTES
    #>

    [CmdLetBinding()]
    param (
        [parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,
        [parameter(Mandatory = $true)]
        [string]$Title
    )

    $Rows | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10 | Out-GridView -Title $Title
}
