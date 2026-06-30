function Initialize-UiComponents {
    <#
    .SYNOPSIS
        Initializes the UI components of the application.

    .DESCRIPTION
        This function initializes the UI components of the application, including loading assemblies, setting up configuration and runtime data, and preparing the main form for display.

    .EXAMPLE
        Initialize-UiComponents

    .NOTES
    #>


    #Initialize UI DataGridQueryResult context menu items
    $Script:DataGridQueryResultMenuItemCopy = $null
    $Script:DataGridQueryResultMenuItemCopyWithHeader = $null
    $Script:DataGridQueryResultMenuItemSelectAll = $null
    $Script:DataGridQueryResultMenuItemSaveAs = $null

    $MenuItems = @($Script:MainForm.Elements.DataGridQueryResult.ContextMenu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] })

    $Script:DataGridQueryResultMenuItemCopy = $MenuItems[0]
    $Script:DataGridQueryResultMenuItemCopyWithHeader = $MenuItems[1]
    $Script:DataGridQueryResultMenuItemSelectAll = $MenuItems[2]
    $Script:DataGridQueryResultMenuItemSaveAs = $MenuItems[3]
}
