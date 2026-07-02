function Update-DataGridQueryResultContextMenuState {
    $HasRows = $Script:MainForm.Elements.DataGridQueryResult.Items.Count -gt 0

    if ($null -ne $Script:DataGridQueryResultMenuItemCopy) {
        $Script:DataGridQueryResultMenuItemCopy.IsEnabled = $HasRows
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemCopyWithHeader) {
        $Script:DataGridQueryResultMenuItemCopyWithHeader.IsEnabled = $HasRows
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemSelectAll) {
        $Script:DataGridQueryResultMenuItemSelectAll.IsEnabled = $HasRows
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemSaveAs) {
        $Script:DataGridQueryResultMenuItemSaveAs.IsEnabled = $HasRows
    }

    if ($null -ne $Script:DataGridQueryResultMenuItemCopyAs) {
        $Script:DataGridQueryResultMenuItemCopyAs.IsEnabled = $HasRows
    }
}
