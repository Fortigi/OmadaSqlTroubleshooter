function Get-DataGridSelectedRow {
    <#
    .SYNOPSIS
        The rows a data grid's selection is in, for grids that select as the result grid does.

    .DESCRIPTION
        With SelectionUnit CellOrRowHeader (Theme.DataGridStyle) a grid's SelectedItem is only set
        for a row picked from its row header: select cells and it stays empty. So the rows are read
        from everything that can be selected - whole rows (SelectedItems) and the rows of the
        selected cells (SelectedCells) - and, when nothing is selected, the row of the cell with the
        focus (CurrentItem).

        Code that needs one row (show a version, act on a query) takes the result when it holds
        exactly one, and says so otherwise, rather than guessing which one was meant.

    .PARAMETER Grid
        The DataGrid.

    .OUTPUTS
        The distinct rows, in the order they were first seen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Grid
    )

    if ($null -eq $Grid) {
        return @()
    }

    $Private:Rows = @(Get-DataGridSelectionRow -Item (@($Grid.SelectedItems) + @($Grid.SelectedCells | ForEach-Object { $_.Item })))
    if ($Private:Rows.Count -eq 0) {
        $Private:Rows = @(Get-DataGridSelectionRow -Item @($Grid.CurrentItem))
    }
    return $Private:Rows
}

function Get-DataGridSelectionRow {
    <#
    .SYNOPSIS
        The distinct rows behind a grid selection.

    .DESCRIPTION
        A row appears once for every selected cell in it, and again when the row itself is selected;
        it is counted once. Rows are told apart by reference, not by their text: two versions with the
        same values are still two rows. The grid's new-item placeholder (an MS.Internal.NamedObject)
        is not a row, and is left out.

    .PARAMETER Item
        The selected items and the items of the selected cells.

    .OUTPUTS
        The distinct rows, in the order they were first seen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Item = @()
    )

    # A plain list and ReferenceEquals: a selection is a handful of rows, and
    # ReferenceEqualityComparer needs .NET 5 where the module still allows PowerShell 7.0.
    $Private:Seen = [System.Collections.Generic.List[object]]::new()
    foreach ($Private:Candidate in @($Item | Where-Object { $null -ne $_ -and $_.GetType().Name -ne "NamedObject" })) {
        if (-not @($Private:Seen | Where-Object { [object]::ReferenceEquals($_, $Private:Candidate) })) {
            $Private:Seen.Add($Private:Candidate)
        }
    }
    return $Private:Seen.ToArray()
}
