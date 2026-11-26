# UI theme

The application's look - colours, fonts, tabs, toolbar, dialog buttons and data grids - is defined
once, in [`src/Lib/ui/Theme.xaml`](../src/Lib/ui/Theme.xaml). Change it there and every window
follows.

## How it reaches a window

`Initialize-FormObject` merges `Theme.xaml` into the XAML of every window, and of the per-tab
content, **before** the XAML is loaded (`Merge-XamlTheme`). A window therefore uses the theme's keys
with `StaticResource` exactly as if it had declared them itself.

- The theme's resources go first in the window's resources, so the window's own styles can build on
  them (`BasedOn="{StaticResource Theme.DialogButtonStyle}"`).
- A window that declares a resource with the same key, or an implicit style for the same type, keeps
  its own. The theme never overrides a window, so a deliberate exception is visible in that window's
  XAML.
- `tests/Merge-XamlTheme.Tests.ps1` merges the theme into every window and fails on any
  `StaticResource` key that does not resolve - the error WPF would otherwise only raise when that
  window opens.

## Keys

| Key | What it is for |
|---|---|
| `Theme.AccentBrush` | The navy accent (`#293955`): the frame around the main window's tabs |
| `Theme.BorderBrush` | Borders of tabs, the toolbar and tab pages (`#8A97A6`) |
| `Theme.TabBrush` / `Theme.TabHoverBrush` / `Theme.TabSelectedBrush` | Tab backgrounds: inactive, hover, selected (Khaki, the status bar's colour) |
| `Theme.ToolbarBrush` | The toolbar band (`#E4E8EC`, the tabs' hover colour) |
| `Theme.MenuBrush` | The menu bar |
| `Theme.TextBrush` / `Theme.MutedTextBrush` | Normal and secondary text |
| `Theme.GridLineBrush` / `Theme.AlternatingRowBrush` | Data grid lines and alternate rows |
| `Theme.HoverBrush` / `Theme.HoverBorderBrush` / `Theme.PressedBrush` | Flat (toolbar) button states |
| `Theme.UiFont` / `Theme.CodeFont` / `Theme.GlyphFont` | Segoe UI, Consolas, the Segoe icon fonts |
| *(implicit)* `TabItem` | Every tab in every window: square, blue-grey, Khaki when selected |
| `Theme.TabControlStyle` | A TabControl frame in the border colour |
| `Theme.ToolbarBorderStyle` | The toolbar band: background, border and padding |
| `Theme.GlyphStyle` | An icon (TextBlock with a Segoe icon code point) |
| `Theme.DialogButtonStyle` + `Theme.ButtonTextStyle` | Dialog buttons: the standard raised button with an icon and text |
| `Theme.DataGridStyle` | Read-only grids that select as the result grid does (rows, cells, ranges; `Ctrl+C` copies) |

Only `TabItem` has an implicit style in the theme. Anything else is keyed, because an implicit style
there would reach every control of that type in every window, including controls built in code.

## A new window

```xml
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="My window" Width="800" Height="500" MinWidth="600" MinHeight="350"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="{DynamicResource {x:Static SystemColors.ScrollBarBrushKey}}"
        Name="MyForm">
    <Window.Resources>
        <!-- Every button and grid in this window takes the theme's. -->
        <Style TargetType="Button" BasedOn="{StaticResource Theme.DialogButtonStyle}"/>
        <Style TargetType="DataGrid" BasedOn="{StaticResource Theme.DataGridStyle}"/>
    </Window.Resources>

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TabControl Grid.Row="0">            <!-- tabs take the theme's TabItem style -->
            <TabItem Header="Items">
                <DataGrid x:Name="DataGridItems" AutoGenerateColumns="True"/>
            </TabItem>
        </TabControl>

        <DockPanel Grid.Row="1" Margin="0,8,0,0" LastChildFill="False">
            <Button x:Name="ButtonCloseMyForm" DockPanel.Dock="Right" Margin="0" IsCancel="True">
                <StackPanel Orientation="Horizontal" IsHitTestVisible="False">
                    <TextBlock Style="{StaticResource Theme.GlyphStyle}" Text="&#xE711;"/>
                    <AccessText Style="{StaticResource Theme.ButtonTextStyle}" Text="_Close"/>
                </StackPanel>
            </Button>
        </DockPanel>
    </Grid>
</Window>
```

Then:

- Load it with `Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder "lib\ui\MyForm.xaml")`
  (that is where the theme is merged) and wire its events in `src/Lib/Events/MyForm.*.ps1` with
  `Import-EventObjects -ClassName "MyForm"`.
- Read "the selected row" of a `Theme.DataGridStyle` grid with `Get-DataGridSelectedRow`: with cell
  selection a grid's `SelectedItem` stays empty when cells are selected.
- A command that belongs on the menu bar gets a menu item with a `Tag` (see
  `Resolve-MainMenuItemState`). A keyboard shortcut for it goes in `Get-KeyboardShortcut`, which is
  also what the Help window lists; `tests/Get-KeyboardShortcut.Tests.ps1` holds the menu's
  `InputGestureText` to that list.
- After giving a grid its rows, call `Update-DataGridColumnWidth -Grid <grid>`: it fixes each column's
  width from its widest value over all rows (capped at 400 px, still resizable by hand), so the columns
  do not jump while the grid is scrolled. A list that is filtered in place can pass its whole, unfiltered
  rows with `-Item`, once, so a filter does not change the widths.
- Show SQL that is not edited in a read-only `RichTextBox` filled with `Set-SqlRichText`: it is
  highlighted with the editor's own word lists and colours.
- A toolbar button whose label changes in code gets every label it can show as a hidden placeholder
  (`ToolbarTextPlaceholderStyle` in `MainFormTabContent.xaml`), so its width does not change;
  `tests/ToolbarButtonWidth.Tests.ps1` holds the labels set in code to the placeholders.
