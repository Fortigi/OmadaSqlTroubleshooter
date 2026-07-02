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

    .PARAMETER ColumnOrder
        Optional column header names, in the order they should be displayed. The JSON sanitize round-trip does
        not preserve property order (it rebuilds objects through an unordered Hashtable), so without this the
        columns Out-GridView shows can end up in a different order than the DataGrid. When provided, the
        sanitized rows are piped through Select-Object to restore the intended order without needing to change
        how the sanitize step itself works.

    .EXAMPLE
        Show-QueryResultGridView -Rows $Script:RunTimeData.QueryResult.d.rows -Title "My Query" -ColumnOrder @("UID", "Number")

    .NOTES
    #>

    [CmdLetBinding()]
    param (
        [parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,
        [parameter(Mandatory = $true)]
        [string]$Title,
        [string[]]$ColumnOrder
    )

    $SanitizedRows = $Rows | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10
    if ($null -ne $ColumnOrder -and $ColumnOrder.Count -gt 0) {
        $SanitizedRows = $SanitizedRows | Select-Object -Property $ColumnOrder
    }

    $SanitizedRows | Out-GridView -Title $Title
}
