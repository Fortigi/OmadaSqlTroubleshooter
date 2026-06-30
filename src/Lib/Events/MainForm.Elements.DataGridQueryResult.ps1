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
            $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::ExcludeHeader
            [System.Windows.Input.ApplicationCommands]::Copy.Execute($null, $Script:MainForm.Elements.DataGridQueryResult)
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:DataGridQueryResultMenuItemCopyWithHeader.Add_Click({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::IncludeHeader
            [System.Windows.Input.ApplicationCommands]::Copy.Execute($null, $Script:MainForm.Elements.DataGridQueryResult)
            $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::ExcludeHeader
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
                "Ctrl+Shift+C key intercepted at DataGrid level - copying values only" | Write-LogOutput -LogType VERBOSE

                $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::IncludeHeader
                [System.Windows.Input.ApplicationCommands]::Copy.Execute($null, $Script:MainForm.Elements.DataGridQueryResult)
                $EventArguments.Handled = $true
            }
            elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::C -and $ControlPressed) {
                "Ctrl+C key intercepted at DataGrid level - copying values with headers" | Write-LogOutput -LogType VERBOSE

                $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::ExcludeHeader
                [System.Windows.Input.ApplicationCommands]::Copy.Execute($null, $Script:MainForm.Elements.DataGridQueryResult)
                $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::IncludeHeader
                $EventArguments.Handled = $true
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

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
