$Script:MainForm.Elements.DataGridQueryResult.ContextMenu.Add_Opened({
        try {
            $_ | Show-EventInfo
            Update-DataGridQueryResultContextMenuState
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

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
            $Script:MainForm.Elements.DataGridQueryResult.SelectAll()
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
            Save-QueryResultToFile -QueryResult (Get-DataGridSelectedQueryResult)
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemViewSelected.Add_Click({
        try {
            $_ | Show-EventInfo
            $SelectedQueryResult = Get-DataGridSelectedQueryResult
            Show-QueryResultGridView -Rows $SelectedQueryResult.d.rows -Title ("{0} - {1} (Selection)" -f $Form.Text, $Script:AppConfig.CurrentSqlQuery.FullName)
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.DataGridQueryResult.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArguments
        )
        try {
            $_ | Show-EventInfo

            $ControlPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
            $ShiftPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift

            if ($EventArguments.Key -eq [System.Windows.Input.Key]::C -and $ControlPressed -and $ShiftPressed) {
                "Ctrl+Shift+C key intercepted at DataGrid level - copying values with headers" | Write-LogOutput -LogType VERBOSE
                $Script:DataGridQueryResultMenuItemCopyWithHeader.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                $EventArguments.Handled = $true
            }
            elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::C -and $ControlPressed -and -not $ShiftPressed) {
                "Ctrl+C key intercepted at DataGrid level - copying values only" | Write-LogOutput -LogType VERBOSE
                $Script:DataGridQueryResultMenuItemCopy.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                $EventArguments.Handled = $true
            }
            elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::P -and $ControlPressed -and $ShiftPressed) {
                "Ctrl+Shift+P key intercepted at DataGrid level - copying values only as PowerShell array" | Write-LogOutput -LogType VERBOSE
                $Script:DataGridQueryResultMenuItemCopyAsPowerShellArray.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                $EventArguments.Handled = $true
            }
            elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::S -and $ControlPressed -and $ShiftPressed) {
                "Ctrl+Shift+S key intercepted at DataGrid level - copying values only as Sql array" | Write-LogOutput -LogType VERBOSE
                $Script:DataGridQueryResultMenuItemCopyAsSqlArray.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                $EventArguments.Handled = $true
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.DataGridQueryResult.AddHandler(
    [System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent,
    [System.Windows.Input.MouseButtonEventHandler] {
        param(
            $EventSender,
            $EventArguments
        )
        try {
            if ($EventArguments.OriginalSource -is [System.Windows.Controls.Primitives.Thumb]) {
                return
            }

            $VisualElement = $EventArguments.OriginalSource
            $ColumnHeader = $null
            while ($null -ne $VisualElement) {
                if ($VisualElement -is [System.Windows.Controls.Primitives.DataGridColumnHeader]) {
                    $ColumnHeader = $VisualElement
                    break
                }
                $VisualElement = [System.Windows.Media.VisualTreeHelper]::GetParent($VisualElement)
            }

            if ($null -eq $ColumnHeader -or $null -eq $ColumnHeader.Column) {
                return
            }

            $_ | Show-EventInfo

            $ControlPressed = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)
            $ShiftPressed = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)

            Select-DataGridColumnCells -DataGrid $Script:MainForm.Elements.DataGridQueryResult -Column $ColumnHeader.Column -ControlPressed $ControlPressed -ShiftPressed $ShiftPressed
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    }
)

$Script:MainForm.Elements.DataGridQueryResult.Add_AutoGeneratingColumn({
        param(
            $EventSender,
            $EventArguments
        )
        try {
            $Private:HeaderTemplate = [System.Windows.Markup.XamlReader]::Parse(
                '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding}" TextTrimming="CharacterEllipsis"/></DataTemplate>'
            )
            $EventArguments.Column.HeaderTemplate = $Private:HeaderTemplate
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.DataGridQueryResult.Add_LoadingRow({
        param(
            $EventSender,
            $EventArguments
        )
        $_ | Show-EventInfo

        try {
            $EventArguments.Row.Header = ($EventArguments.Row.GetIndex() + 1).ToString()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
