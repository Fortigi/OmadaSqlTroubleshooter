# The Results context menu's commands (issue #151).
#
# What this file used to be: nine subscriptions wired ONCE, at module load, to the single named
# DataGridQueryResult - its context menu, its key presses, its column-header clicks, its column
# generation and its row loading.
#
# That element no longer exists. The Results pane holds one grid per statement, created by the
# ItemsControl from its DataTemplate after load and replaced on every execute, so anything bound to a
# grid has to be bound per grid as each one is realised. Those six handlers now live in
# Register-QueryResultGridHandler, which the execute completion calls once the containers exist.
#
# What stays here is what is NOT bound to a grid: the menu item clicks. The menu is a single shared
# resource and Initialize-UiComponents resolves these seven $Script: variables from it - positionally,
# which is why the item order in MainFormTabContent.xaml is load-bearing. Each command then acts on
# whichever result has focus, through Get-FocusedQueryResultGrid and Get-FocusedQueryResult.

$Script:DataGridQueryResultMenuItemCopy.Add_Click({
        try {
            $_ | Show-EventInfo
            Copy-DataGridToClipboard
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemCopyWithHeader.Add_Click({
        try {
            $_ | Show-EventInfo
            Copy-DataGridToClipboard -IncludeHeader
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemCopyAsSqlArray.Add_Click({
        try {
            $_ | Show-EventInfo
            Copy-DataGridToClipboard -OutputFormat "SqlArray"
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemCopyAsPowerShellArray.Add_Click({
        try {
            $_ | Show-EventInfo
            Copy-DataGridToClipboard -OutputFormat "PowerShellArray"
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemSelectAll.Add_Click({
        try {
            $_ | Show-EventInfo

            # The focused result's grid, not "the" grid: Select All on a stack of results has to mean
            # the one the user opened the menu over.
            $Private:FocusedGrid = Get-FocusedQueryResultGrid
            if ($null -ne $Private:FocusedGrid) {
                $Private:FocusedGrid.SelectAll()
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemSaveAs.Add_Click({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.Elements.ButtonSaveOutputFile.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemSaveSelectedAs.Add_Click({
        try {
            $_ | Show-EventInfo
            Save-QueryResultToFile -QueryResult (Get-DataGridSelectedQueryResult) -IsSelection
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemViewSelected.Add_Click({
        try {
            $_ | Show-EventInfo
            $SelectedQueryResult = Get-DataGridSelectedQueryResult
            $ColumnOrder = @($SelectedQueryResult.d.rows | Select-Object -First 1 | ForEach-Object { $_.PSObject.Properties.Name })
            Show-QueryResultGridView -Rows $SelectedQueryResult.d.rows -Title ("{0} - {1} (Selection)" -f $Form.Text, $Script:AppConfig.CurrentSqlQuery.FullName) -ColumnOrder $ColumnOrder
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
