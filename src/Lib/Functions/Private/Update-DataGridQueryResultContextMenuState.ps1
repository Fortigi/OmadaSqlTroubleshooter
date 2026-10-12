function Update-DataGridQueryResultContextMenuState {
    # The focused result's grid (issue #151). The menu is one shared instance across the stack now, so
    # what it may do depends on the grid the user opened it over - not on "the" grid, which no longer
    # exists.
    #
    # Resolved ONCE: Get-FocusedQueryResultGrid walks the item container's visual tree, and asking
    # twice would walk it twice for one answer on a path that runs every time the menu opens.
    $Private:DataGrid = Get-FocusedQueryResultGrid

    # A null grid disables everything rather than throwing, which is the honest answer when there is
    # no result to act on - before the first execute, or after a disconnect cleared the pane.
    $HasRows = $null -ne $Private:DataGrid -and $Private:DataGrid.Items.Count -gt 0
    $HasSelection = $null -ne $Private:DataGrid -and $Private:DataGrid.SelectedCells.Count -gt 0

    if ($null -ne $Script:DataGridQueryResultMenuItemCopy) {
        $Script:DataGridQueryResultMenuItemCopy.IsEnabled = $HasSelection
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemCopyWithHeader) {
        $Script:DataGridQueryResultMenuItemCopyWithHeader.IsEnabled = $HasSelection
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemSelectAll) {
        $Script:DataGridQueryResultMenuItemSelectAll.IsEnabled = $HasRows
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemSaveAs) {
        $Script:DataGridQueryResultMenuItemSaveAs.IsEnabled = $HasRows
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemCopyAs) {
        $Script:DataGridQueryResultMenuItemCopyAs.IsEnabled = $HasSelection
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemSaveSelectedAs) {
        $Script:DataGridQueryResultMenuItemSaveSelectedAs.IsEnabled = $HasSelection
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemViewSelected) {
        $Script:DataGridQueryResultMenuItemViewSelected.IsEnabled = $HasSelection
    }
}
