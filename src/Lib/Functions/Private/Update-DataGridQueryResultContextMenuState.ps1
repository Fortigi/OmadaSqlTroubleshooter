function Update-DataGridQueryResultContextMenuState {
    $HasRows = $Script:MainForm.Elements.DataGridQueryResult.Items.Count -gt 0
    $HasSelection = $Script:MainForm.Elements.DataGridQueryResult.SelectedCells.Count -gt 0

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
