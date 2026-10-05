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
    $Script:DataGridQueryResultMenuItemSaveSelectedAs = $null
    $Script:DataGridQueryResultMenuItemViewSelected = $null

    # The context menu is a shared resource in MainFormTabContent.xaml now (issue #151), not a child
    # of one DataGrid: the Results pane holds one grid per statement, so there is no single grid left
    # to hang it on, and a menu inside the per-result DataTemplate could not be reached at all -
    # x:Names declared in a template never reach FindName.
    #
    # Resolved from the stack container rather than from $Script:MainForm.Definition. WPF resource
    # lookup walks UP the tree from the element it is asked on, and $Script:MainForm.Definition is
    # MainForm's root - it cannot see a resource declared inside the tab content. The ItemsControl
    # lives in that control, so the lookup succeeds from there.
    #
    # Per tab, without needing to say so: Set-ActiveTabContext repoints $Script:MainForm.Elements onto
    # the active tab's elements and then calls this function, so each tab binds its own menu.
    $Private:ResultContextMenu = $null
    if ($null -ne $Script:MainForm.Elements.ItemsControlQueryResults) {
        $Private:ResultContextMenu = $Script:MainForm.Elements.ItemsControlQueryResults.TryFindResource("DataGridQueryResultContextMenu")
    }

    # Still positional - $MenuItems[0]..[6] below - which is why the item order in the markup is
    # load-bearing and asserted by QueryResultContextMenuIsShared.Tests.ps1.
    $MenuItems = @($Private:ResultContextMenu.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] })

    $Script:DataGridQueryResultMenuItemCopy = $MenuItems[0]
    $Script:DataGridQueryResultMenuItemCopyWithHeader = $MenuItems[1]
    $Script:DataGridQueryResultMenuItemCopyAs = $MenuItems[2]
    $Script:DataGridQueryResultMenuItemSelectAll = $MenuItems[3]
    $Script:DataGridQueryResultMenuItemSaveAs = $MenuItems[4]
    $Script:DataGridQueryResultMenuItemSaveSelectedAs = $MenuItems[5]
    $Script:DataGridQueryResultMenuItemViewSelected = $MenuItems[6]

    $CopyAsMenuItems = @($Script:DataGridQueryResultMenuItemCopyAs.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] })

    $Script:DataGridQueryResultMenuItemCopyAsSqlArray = $CopyAsMenuItems[0]
    $Script:DataGridQueryResultMenuItemCopyAsPowerShellArray = $CopyAsMenuItems[1]

    #Initialize UI DataGridQueryResult column selection anchor
    $Script:DataGridQueryResultColumnSelectionAnchor = $null

    # Execute/Cancel (issue #40). Set-ActiveTabContext calls this on every tab switch, so switching to
    # a tab whose query is still running shows Cancel, and switching away and back does not lose it.
    # Derived from the completion queue, so it is correct here without any per-tab flag to keep in
    # step - which is the same reason Test-ConnectionButton can be called freely.
    Set-ExecuteQueryButtonState
}
