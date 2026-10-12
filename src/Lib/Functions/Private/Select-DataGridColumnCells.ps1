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

function Clear-DataGridColumnSelectionAnchor {
    <#
    .SYNOPSIS
        Forgets the column a shift-click would range-select from.

    .DESCRIPTION
        Issue #166. The anchor is module-scope state that Select-DataGridColumnCells above owns, and
        moving focus to another result has to clear it: without that, a shift-click in the newly
        focused grid range-selects from a column in the grid the user has just left.

        A FUNCTION rather than the bare assignment it replaces. The GotFocus handler in
        Register-QueryResultGridHandler used to be a .GetNewClosure() scriptblock, and a closure runs
        in a detached dynamic module whose scope does not include this module's $Script: variables -
        so the `$Script:DataGridQueryResultColumnSelectionAnchor = $null` written there landed in the
        closure's own scope and the variable this file reads was never cleared. The clear was a
        no-op, silently: no error and no log line, leaving exactly the behaviour the handler existed
        to prevent.

        The closure could not reach this FUNCTION either, in the installed module (issue #169): a
        closure resolves commands through the global scope, which only sees the three functions the
        .psd1 exports. So the handler is now a plain scriptblock, and the write still lives here, in
        the file that owns the state.

        No parameters, and deliberately no WPF types in its signature, so it can be exercised in the
        headless test lane where System.Windows.* does not resolve.

        No tracer preamble: this runs on every focus change between results, and the preamble would
        add a line per click for a state reset that has nothing in it worth tracing.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param()

    $Script:DataGridQueryResultColumnSelectionAnchor = $null
}
