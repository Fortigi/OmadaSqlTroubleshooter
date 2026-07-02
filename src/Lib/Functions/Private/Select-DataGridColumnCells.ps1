function Select-DataGridColumnCells {
    <#
    .SYNOPSIS
        Selects all cells within a DataGrid column, honoring Ctrl (toggle) and Shift (range) modifiers.

    .DESCRIPTION
        Implements column-header click selection for a DataGrid: a plain click selects the full clicked column,
        Ctrl+click toggles the clicked column within the existing selection, and Shift+click selects the
        contiguous range of columns between the last clicked column and the current one. The last clicked
        column is tracked in $Script:DataGridQueryResultColumnSelectionAnchor so range selection keeps working
        across multiple calls.

    .PARAMETER DataGrid
        The DataGrid whose SelectedCells collection should be updated.

    .PARAMETER Column
        The DataGridColumn that was clicked.

    .PARAMETER ControlPressed
        Whether the Control key was held down during the click.

    .PARAMETER ShiftPressed
        Whether the Shift key was held down during the click.

    .EXAMPLE
        Select-DataGridColumnCells -DataGrid $DataGrid -Column $ColumnHeader.Column -ControlPressed $false -ShiftPressed $false

    .NOTES
    #>

    [CmdLetBinding()]
    param (
        [parameter(Mandatory = $true)]
        [System.Windows.Controls.DataGrid]$DataGrid,
        [parameter(Mandatory = $true)]
        [System.Windows.Controls.DataGridColumn]$Column,
        [parameter(Mandatory = $true)]
        [bool]$ControlPressed,
        [parameter(Mandatory = $true)]
        [bool]$ShiftPressed
    )

    try {
        if ($ShiftPressed -and $null -ne $Script:DataGridQueryResultColumnSelectionAnchor) {
            $StartIndex = [math]::Min($Script:DataGridQueryResultColumnSelectionAnchor.DisplayIndex, $Column.DisplayIndex)
            $EndIndex = [math]::Max($Script:DataGridQueryResultColumnSelectionAnchor.DisplayIndex, $Column.DisplayIndex)
            $RangeColumns = @($DataGrid.Columns | Where-Object { $_.DisplayIndex -ge $StartIndex -and $_.DisplayIndex -le $EndIndex })

            $DataGrid.SelectedCells.Clear()
            foreach ($RangeColumn in $RangeColumns) {
                foreach ($Row in $DataGrid.Items) {
                    $DataGrid.SelectedCells.Add([System.Windows.Controls.DataGridCellInfo]::new($Row, $RangeColumn))
                }
            }
        }
        elseif ($ControlPressed) {
            $ColumnCells = @($DataGrid.Items | ForEach-Object { [System.Windows.Controls.DataGridCellInfo]::new($_, $Column) })
            $ColumnFullySelected = @($ColumnCells | Where-Object { $DataGrid.SelectedCells.Contains($_) }).Count -eq $ColumnCells.Count

            if ($ColumnFullySelected) {
                foreach ($ColumnCell in $ColumnCells) {
                    $DataGrid.SelectedCells.Remove($ColumnCell) | Out-Null
                }
            }
            else {
                foreach ($ColumnCell in $ColumnCells) {
                    if (-not $DataGrid.SelectedCells.Contains($ColumnCell)) {
                        $DataGrid.SelectedCells.Add($ColumnCell)
                    }
                }
            }

            $Script:DataGridQueryResultColumnSelectionAnchor = $Column
        }
        else {
            $DataGrid.SelectedCells.Clear()
            foreach ($Row in $DataGrid.Items) {
                $DataGrid.SelectedCells.Add([System.Windows.Controls.DataGridCellInfo]::new($Row, $Column))
            }

            $Script:DataGridQueryResultColumnSelectionAnchor = $Column
        }

        $DataGrid.Focus() | Out-Null
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
