function Get-DataGridSelectedQueryResult {
    <#
    .SYNOPSIS
        Builds a QueryResult-shaped object containing only the currently selected DataGrid cells.

    .DESCRIPTION
        Extracts the unique selected columns (ordered by DisplayIndex) and the rows that have at least one
        selected cell from DataGridQueryResult.SelectedCells, and returns them as an object shaped like
        $Script:RunTimeData.QueryResult (a "d.rows" wrapper), so the existing save-to-file and Out-GridView
        code paths can consume it unchanged. Each row becomes a PSCustomObject with one property per selected
        column (using the column header as the property name), even if that specific cell was not individually
        selected. A uniform property set across every row is required here because Export-Csv, Format-Table
        and Out-GridView all derive their displayed columns from the first object in the collection; unlike
        Copy-DataGridToClipboard (plain text, one line per row), leaving out an individually unselected cell's
        property would silently hide that column for every other row.

    .EXAMPLE
        Get-DataGridSelectedQueryResult

    .NOTES
    #>

    [CmdLetBinding()]
    param ()

    $DataGrid = $Script:MainForm.Elements.DataGridQueryResult

    $SelectedColumnSet = [System.Collections.Generic.HashSet[object]]::new()
    $SelectedColumns = [System.Collections.Generic.List[object]]::new()
    foreach ($SelectedCell in $DataGrid.SelectedCells) {
        if ($SelectedColumnSet.Add($SelectedCell.Column)) {
            $SelectedColumns.Add($SelectedCell.Column)
        }
    }
    $SelectedColumns = @($SelectedColumns | Sort-Object -Property DisplayIndex)

    $SelectedRowSet = [System.Collections.Generic.HashSet[object]]::new()
    foreach ($SelectedCell in $DataGrid.SelectedCells) {
        $SelectedRowSet.Add($SelectedCell.Item) | Out-Null
    }
    $SelectedRows = @($DataGrid.Items | Where-Object { $SelectedRowSet.Contains($_) })

    $ResultRows = [System.Collections.Generic.List[object]]::new()
    foreach ($Row in $SelectedRows) {
        $RowProperties = [ordered]@{}
        foreach ($Column in $SelectedColumns) {
            $CellInfo = [System.Windows.Controls.DataGridCellInfo]::new($Row, $Column)
            if ($DataGrid.SelectedCells.Contains($CellInfo)) {
                $RowProperties["{0}" -f $Column.Header] = $Column.OnCopyingCellClipboardContent($Row)
            }
            else {
                $RowProperties["{0}" -f $Column.Header] = $null
            }
        }
        $ResultRows.Add([PSCustomObject]$RowProperties)
    }

    return [PSCustomObject]@{
        d = [PSCustomObject]@{
            rows = @($ResultRows)
        }
    }
}
