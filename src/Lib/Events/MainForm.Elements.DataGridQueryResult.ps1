# $Script:MainForm.Elements.DataGridQueryResult.Add_PreviewKeyDown({
#         [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'EventArgs', Justification = 'The use of the variable is on purpose')]
#         param(
#             $EventSender,
#             $EventArgs
#         )
#         try {
#             $_ | Show-EventInfo

#             if ($EventArgs.Key -eq [System.Windows.Input.Key]::C -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
#                 "Ctrl+C pressed in DataGrid - copying selected content" | Write-LogOutput -LogType DEBUG

#                 try {
#                     $ClipboardText = ""
#                     $SelectedCells = $Script:MainForm.Elements.DataGridQueryResult.SelectedCells
#                     $SelectedItems = $Script:MainForm.Elements.DataGridQueryResult.SelectedItems

#                     # Check if we have a "select all" scenario by looking at current cell and selection
#                     $CurrentCell = $Script:MainForm.Elements.DataGridQueryResult.CurrentCell
#                     $IsSelectAll = ($SelectedItems.Count -eq 0 -and $SelectedCells.Count -eq 0 -and
#                         $Script:MainForm.Elements.DataGridQueryResult.Items.Count -gt 0) -or
#                     ($CurrentCell.Item -eq $Null -and $CurrentCell.Column -eq $Null)

#                     if ($IsSelectAll) {
#                         # Handle "select all" from top-left corner - copy all data
#                         "Copying all data (select all scenario)" | Write-LogOutput -LogType DEBUG
#                         $AllItems = $Script:MainForm.Elements.DataGridQueryResult.Items
#                         $Columns = $Script:MainForm.Elements.DataGridQueryResult.Columns

#                         $RowData = @()

#                         # Add header row
#                         $HeaderValues = @()
#                         foreach ($Column in $Columns) {
#                             if ($Column.Visibility -eq [System.Windows.Visibility]::Visible) {
#                                 $HeaderValues += if ($Null -ne $Column.Header) { $Column.Header.ToString() } else { "" }
#                             }
#                         }
#                         $RowData += $HeaderValues -join "`t"

#                         # Add all data rows
#                         foreach ($Item in $AllItems) {
#                             $RowValues = @()
#                             foreach ($Column in $Columns) {
#                                 if ($Column.Visibility -eq [System.Windows.Visibility]::Visible) {
#                                     $CellValue = ""
#                                     if ($Null -ne $Column.Header) {
#                                         $PropertyName = $Column.Header.ToString()
#                                         if ($Item.PSObject.Properties[$PropertyName]) {
#                                             $CellValue = $Item.$PropertyName
#                                         }
#                                         elseif ($Item -is [System.Data.DataRowView]) {
#                                             $CellValue = $Item[$PropertyName]
#                                         }
#                                         elseif ($Item -is [PSCustomObject]) {
#                                             $CellValue = $Item.$PropertyName
#                                         }
#                                     }
#                                     $RowValues += if ($Null -eq $CellValue) { "" } else { $CellValue.ToString() }
#                                 }
#                             }
#                             $RowData += $RowValues -join "`t"
#                         }

#                         $ClipboardText = $RowData -join "`r`n"
#                         "Copied all {0} row(s) to clipboard" -f $AllItems.Count | Write-LogOutput -LogType DEBUG
#                     }
#                     elseif ($SelectedItems.Count -gt 0 -and $SelectedCells.Count -eq 0) {
#                         "Copying {0} selected row(s)" -f $SelectedItems.Count | Write-LogOutput -LogType DEBUG

#                         $RowData = @()
#                         $Columns = $Script:MainForm.Elements.DataGridQueryResult.Columns

#                         if ($SelectedItems.Count -gt 1) {
#                             $HeaderValues = @()
#                             foreach ($Column in $Columns) {
#                                 if ($Column.Visibility -eq [System.Windows.Visibility]::Visible) {
#                                     $HeaderValues += if ($Null -ne $Column.Header) { $Column.Header.ToString() } else { "" }
#                                 }
#                             }
#                             $RowData += $HeaderValues -join "`t"
#                         }

#                         foreach ($Item in $SelectedItems) {
#                             $RowValues = @()
#                             foreach ($Column in $Columns) {
#                                 if ($Column.Visibility -eq [System.Windows.Visibility]::Visible) {
#                                     $CellValue = ""
#                                     if ($Null -ne $Column.Header) {
#                                         $PropertyName = $Column.Header.ToString()
#                                         if ($Item.PSObject.Properties[$PropertyName]) {
#                                             $CellValue = $Item.$PropertyName
#                                         }
#                                         elseif ($Item -is [System.Data.DataRowView]) {
#                                             $CellValue = $Item[$PropertyName]
#                                         }
#                                         elseif ($Item -is [PSCustomObject]) {
#                                             $CellValue = $Item.$PropertyName
#                                         }
#                                     }
#                                     $RowValues += if ($Null -eq $CellValue) { "" } else { $CellValue.ToString() }
#                                 }
#                             }
#                             $RowData += $RowValues -join "`t"
#                         }

#                         $ClipboardText = $RowData -join "`r`n"
#                         "Copied {0} row(s) to clipboard" -f $SelectedItems.Count | Write-LogOutput -LogType DEBUG
#                     }
#                     elseif ($SelectedCells.Count -gt 0) {
#                         "Copying {0} selected cell(s)" -f $SelectedCells.Count | Write-LogOutput -LogType DEBUG

#                         $CellValues = @()

#                         foreach ($Cell in $SelectedCells) {
#                             if ($Null -ne $Cell.Item -and $Null -ne $Cell.Column) {
#                                 $CellValue = ""

#                                 if ($Cell.Column.Header) {
#                                     $PropertyName = $Cell.Column.Header.ToString()
#                                     if ($Cell.Item.PSObject.Properties[$PropertyName]) {
#                                         $CellValue = $Cell.Item.$PropertyName
#                                     }
#                                     elseif ($Cell.Item -is [System.Data.DataRowView]) {
#                                         $CellValue = $Cell.Item[$PropertyName]
#                                     }
#                                     elseif ($Cell.Item -is [PSCustomObject]) {
#                                         $CellValue = $Cell.Item.$PropertyName
#                                     }
#                                 }

#                                 if ([string]::IsNullOrEmpty($CellValue)) {
#                                     $CellValue = $Cell.Item.ToString()
#                                 }

#                                 $CellValues += if ($Null -eq $CellValue) { "" } else { $CellValue.ToString() }
#                             }
#                         }

#                         $ClipboardText = $CellValues -join "`t"
#                     }
#                     else {
#                         "No cells or rows selected for copying" | Write-LogOutput -LogType WARNING
#                         return
#                     }

#                     if (![string]::IsNullOrEmpty($ClipboardText)) {
#                         # Set clipboard with proper data object for Excel compatibility
#                         $DataObject = New-Object System.Windows.DataObject
#                         $DataObject.SetData([System.Windows.TextDataFormat]::Text,$ClipboardText)
#                         $DataObject.SetData([System.Windows.TextDataFormat]::UnicodeText,$ClipboardText)
#                         [System.Windows.Clipboard]::SetDataObject($DataObject, $True)

#                         $EventArgs.Handled = $True
#                         $Preview = $ClipboardText.Substring(0, [Math]::Min(100, $ClipboardText.Length))
#                         if ($ClipboardText.Length -gt 100) { $Preview += "..." }
#                         "Content copied to clipboard: {0}" -f $Preview | Write-LogOutput -LogType DEBUG

#                     }
#                     else {
#                         "No content found in selected cells/rows" | Write-LogOutput -LogType WARNING
#                     }
#                 }
#                 catch {
#                     "Error copying cell content: {0}" -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
#                 }
#             }
#         }
#         catch {
#             $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
#         }
#     })

# $Script:MainForm.Elements.DataGridQueryResult.Add_MouseDoubleClick({
#         [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'EventArgs', Justification = 'The use of the variable is on purpose')]
#         param(
#             $EventSender,
#             $EventArgs
#         )
#         try {
#             $_ | Show-EventInfo

#             $HitTest = [System.Windows.Media.VisualTreeHelper]::HitTest($Script:MainForm.Elements.DataGridQueryResult, $EventArgs.GetPosition($Script:MainForm.Elements.DataGridQueryResult))

#             if ($Null -ne $HitTest.VisualHit) {
#                 $Cell = $HitTest.VisualHit
#                 while ($Null -ne $Cell -and $Cell -isnot [System.Windows.Controls.DataGridCell]) {
#                     $Cell = [System.Windows.Media.VisualTreeHelper]::GetParent($Cell)
#                 }

#                 if ($Null -ne $Cell -and $Cell -is [System.Windows.Controls.DataGridCell]) {
#                     try {
#                         $CellValue = ""
#                         $DataContext = $Cell.DataContext
#                         $Column = $Cell.Column

#                         if ($Null -ne $DataContext -and $Null -ne $Column -and $Null -ne $Column.Header) {
#                             $PropertyName = $Column.Header.ToString()

#                             if ($DataContext.PSObject.Properties[$PropertyName]) {
#                                 $CellValue = $DataContext.$PropertyName
#                             }
#                             elseif ($DataContext -is [System.Data.DataRowView]) {
#                                 $CellValue = $DataContext[$PropertyName]
#                             }
#                             elseif ($DataContext -is [PSCustomObject]) {
#                                 $CellValue = $DataContext.$PropertyName
#                             }
#                         }

#                         if ($Null -ne $CellValue -and ![string]::IsNullOrEmpty($CellValue.ToString())) {
#                             # Set clipboard with proper data object for Excel compatibility
#                             $DataObject = New-Object System.Windows.DataObject
#                             $CellText = $CellValue.ToString()
#                             $DataObject.SetText($CellText, [System.Windows.TextDataFormat]::Text)
#                             $DataObject.SetText($CellText, [System.Windows.TextDataFormat]::UnicodeText)
#                             [System.Windows.Clipboard]::SetDataObject($DataObject, $True)

#                             $EventArgs.Handled = $True
#                             "Double-click: Copied cell content to clipboard: {0}" -f ($CellText.Substring(0, [Math]::Min(50, $CellText.Length))) | Write-LogOutput -LogType DEBUG
#                         }
#                         else {
#                             "Double-click: No content found in clicked cell" | Write-LogOutput -LogType WARNING
#                         }
#                     }
#                     catch {
#                         "Error copying double-clicked cell content: {0}" -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
#                     }
#                 }
#             }
#         }
#         catch {
#             $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
#         }
#     })

$Private:ContextMenu = [System.Windows.Markup.XamlReader]::Parse(@'
<ContextMenu xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             FontFamily="Segoe UI" FontSize="13" Foreground="#666666">
    <ContextMenu.Template>
        <ControlTemplate TargetType="ContextMenu">
            <Border Background="White" BorderBrush="#E0E0E0" BorderThickness="1"
                    CornerRadius="4" Margin="6" SnapsToDevicePixels="True">
                <Border.Effect>
                    <DropShadowEffect BlurRadius="8" ShadowDepth="2" Opacity="0.2" Color="Black"/>
                </Border.Effect>
                <ItemsPresenter Margin="0,4"/>
            </Border>
        </ControlTemplate>
    </ContextMenu.Template>
    <ContextMenu.Resources>
        <ControlTemplate x:Key="FlatMenuItem" TargetType="MenuItem">
            <Border x:Name="Border" Background="Transparent" Padding="32,8,40,8">
                <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/>
            </Border>
            <ControlTemplate.Triggers>
                <Trigger Property="IsHighlighted" Value="True">
                    <Setter TargetName="Border" Property="Background" Value="#0078D7"/>
                    <Setter Property="Foreground" Value="White"/>
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>
    </ContextMenu.Resources>
    <MenuItem Header="Copy" Template="{StaticResource FlatMenuItem}"/>
    <MenuItem Header="Copy with Headers" Template="{StaticResource FlatMenuItem}"/>
</ContextMenu>
'@)
$Private:MenuItemCopy = $Private:ContextMenu.Items[0]
$Private:MenuItemCopyWithHeader = $Private:ContextMenu.Items[1]
$Script:MainForm.Elements.DataGridQueryResult.ContextMenu = $Private:ContextMenu

$Private:MenuItemCopy.Add_Click({
        try {
            $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::ExcludeHeader
            [System.Windows.Input.ApplicationCommands]::Copy.Execute($null, $Script:MainForm.Elements.DataGridQueryResult)
            $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::IncludeHeader
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Private:MenuItemCopyWithHeader.Add_Click({
        try {
            $Script:MainForm.Elements.DataGridQueryResult.ClipboardCopyMode = [System.Windows.Controls.DataGridClipboardCopyMode]::IncludeHeader
            [System.Windows.Input.ApplicationCommands]::Copy.Execute($null, $Script:MainForm.Elements.DataGridQueryResult)
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.DataGridQueryResult.Add_AutoGeneratingColumn({
        param(
            $EventSender,
            $EventArgs
        )
        try {
            $Private:HeaderTemplate = [System.Windows.Markup.XamlReader]::Parse(
                '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding}" TextTrimming="CharacterEllipsis"/></DataTemplate>'
            )
            $EventArgs.Column.HeaderTemplate = $Private:HeaderTemplate
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.DataGridQueryResult.Add_LoadingRow({
        param(
            $EventSender,
            $EventArgs
        )
        $_ | Show-EventInfo

        try {
            $EventArgs.Row.Header = ($EventArgs.Row.GetIndex() + 1).ToString()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })