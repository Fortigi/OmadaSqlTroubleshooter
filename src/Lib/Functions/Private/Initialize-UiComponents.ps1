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
    $Script:DataGridQueryResultMenuItemCopyAs = $null
    $Script:DataGridQueryResultMenuItemCopyAsSqlArray = $null
    $Script:DataGridQueryResultMenuItemCopyAsPowerShellArray = $null
    $Script:DataGridQueryResultMenuItemSelectAll = $null
    $Script:DataGridQueryResultMenuItemSaveAs = $null

    $MenuItems = @($Script:MainForm.Elements.DataGridQueryResult.ContextMenu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] })

    $Script:DataGridQueryResultMenuItemCopy = $MenuItems[0]
    $Script:DataGridQueryResultMenuItemCopyWithHeader = $MenuItems[1]
    $Script:DataGridQueryResultMenuItemCopyAs = $MenuItems[2]
    $Script:DataGridQueryResultMenuItemSelectAll = $MenuItems[3]
    $Script:DataGridQueryResultMenuItemSaveAs = $MenuItems[4]

    $CopyAsMenuItems = @($Script:DataGridQueryResultMenuItemCopyAs.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] })

    $Script:DataGridQueryResultMenuItemCopyAsSqlArray = $CopyAsMenuItems[0]
    $Script:DataGridQueryResultMenuItemCopyAsPowerShellArray = $CopyAsMenuItems[1]
}
