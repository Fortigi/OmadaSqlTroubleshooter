function Register-QueryResultGridHandler {
    <#
    .SYNOPSIS
    Attach the Results grid's event handlers to each per-statement grid, and track which one has focus.

    .DESCRIPTION
    Issue #151. MainFormTabContent.Elements.DataGridQueryResult.ps1 subscribed nine events ONCE, at
    module load, to the single named DataGrid. With one grid per statement there is no such element:
    the grids are created by the ItemsControl from its DataTemplate, after load, and replaced on every
    execute. So the subscriptions move here and are applied per grid, as each one is realised.

    What moved, and what did not. These are the handlers that belong to a GRID and therefore have to
    be attached per grid:

        GotFocus                        which result the commands act on
        PreviewMouseLeftButtonDown      column-header click selection
        PreviewKeyDown                  Ctrl+C / Ctrl+Shift+C / Ctrl+Shift+P / Ctrl+Shift+S
        ContextMenuOpening              the focused result, then the menu's enabled state
        AutoGeneratingColumn            the header template
        LoadingRow                      row numbers

    The five MenuItem.Add_Click handlers stay in the event file. They hang off the
    $Script:DataGridQueryResultMenuItem* variables, which Initialize-UiComponents still resolves -
    positionally - from the shared ContextMenu resource, so they are wired once and act on whichever
    grid is focused.

    IDEMPOTENT, because it has to be. The containers are regenerated on every execute and this runs
    from the same deferred dispatcher callback as the sizing pass, so a grid can be offered to it more
    than once. A second subscription would copy every row to the clipboard twice and raise each
    shortcut twice. The marker is a property on the grid itself rather than a list of seen grids: the
    grids are discarded with their containers, and a module-scope list would hold them alive.

    .PARAMETER TabSession
    The tab whose grids to wire. Defaults to the active tab, which during a background completion is
    the tab the work belongs to.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.Elements) {
            return
        }

        $Private:Items = $Private:Target.Elements.ItemsControlQueryResults
        if ($null -eq $Private:Items -or $Private:Items.Items.Count -le 0) {
            return
        }

        for ($Private:Index = 0; $Private:Index -lt $Private:Items.Items.Count; $Private:Index++) {
            $Private:Container = $Private:Items.ItemContainerGenerator.ContainerFromIndex($Private:Index)
            if ($null -eq $Private:Container) {
                continue
            }

            $Private:Grid = Find-VisualChildDataGrid -Parent $Private:Container
            if ($null -eq $Private:Grid) {
                continue
            }

            # Already wired - see IDEMPOTENT above. Tag is unused by this application's grids, and the
            # value is the ordinal rather than $true so the marker also says WHICH result the grid is,
            # which the focus handlers below close over.
            if ($null -ne $Private:Grid.Tag) {
                continue
            }

            $Private:Grid.Tag = $Private:Index

            # GetNewClosure on every handler: the index has to be the one from THIS iteration. Without
            # it all of them would capture the loop variable and report the last grid, so clicking any
            # result would focus the bottom one.
            #
            # A PLAIN local, deliberately - not $Private:GridIndex. GetNewClosure captures the
            # enclosing scope's variables, and a $Private:-scoped one is not visible to the captured
            # scope when the handler later runs, so every handler saw nothing and
            # Set-FocusedQueryResult ignored the out-of-range index. Measured in the STA probe: the
            # grid took keyboard focus (Focus() returned true, IsKeyboardFocusWithin true) and the
            # focused index still read 0 for the second grid. The $Private: prefix is why.
            $GridIndex = $Private:Index

            $Private:Grid.Add_GotFocus({
                    try {
                        Set-FocusedQueryResult -Index $GridIndex

                        # The column-selection anchor is single-grid state (Select-DataGridColumnCells
                        # keeps it in module scope). Moving focus to another result has to clear it, or
                        # a shift-click in the new grid would range-select from a column in the old one.
                        $Script:DataGridQueryResultColumnSelectionAnchor = $null
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType DEBUG
                    }
                }.GetNewClosure())

            $Private:Grid.Add_ContextMenuOpening({
                    try {
                        # Opening the menu over a grid is itself a statement of which result the user
                        # means - they may never have clicked into it. Focus first, then let the menu
                        # decide what it may offer for that result.
                        Set-FocusedQueryResult -Index $GridIndex
                        Update-DataGridQueryResultContextMenuState
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType DEBUG
                    }
                }.GetNewClosure())

            # $EventSender is deliberately absent from these three handlers. They act on the focused
            # result or on $EventArguments alone, and src/lib/functions is linted with
            # PSReviewUnusedParameter ENABLED - unlike src/lib/events, where the original versions of
            # these handlers declared it unused and the rule is excluded. Declaring it here would fail
            # the build's Analyze task.
            $Private:Grid.Add_PreviewKeyDown({
                    param(
                        $EventArguments
                    )
                    try {
                        Set-FocusedQueryResult -Index $GridIndex

                        $Private:ControlPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
                        $Private:ShiftPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift

                        if ($EventArguments.Key -eq [System.Windows.Input.Key]::C -and $Private:ControlPressed -and $Private:ShiftPressed) {
                            "Ctrl+Shift+C key intercepted at DataGrid level - copying values with headers" | Write-LogOutput -LogType VERBOSE
                            $Script:DataGridQueryResultMenuItemCopyWithHeader.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                            $EventArguments.Handled = $true
                        }
                        elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::C -and $Private:ControlPressed -and -not $Private:ShiftPressed) {
                            "Ctrl+C key intercepted at DataGrid level - copying values only" | Write-LogOutput -LogType VERBOSE
                            $Script:DataGridQueryResultMenuItemCopy.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                            $EventArguments.Handled = $true
                        }
                        elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::P -and $Private:ControlPressed -and $Private:ShiftPressed) {
                            "Ctrl+Shift+P key intercepted at DataGrid level - copying values only as PowerShell array" | Write-LogOutput -LogType VERBOSE
                            $Script:DataGridQueryResultMenuItemCopyAsPowerShellArray.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                            $EventArguments.Handled = $true
                        }
                        elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::S -and $Private:ControlPressed -and $Private:ShiftPressed) {
                            "Ctrl+Shift+S key intercepted at DataGrid level - copying values only as Sql array" | Write-LogOutput -LogType VERBOSE
                            $Script:DataGridQueryResultMenuItemCopyAsSqlArray.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.MenuItem]::ClickEvent))
                            $EventArguments.Handled = $true
                        }
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                    }
                }.GetNewClosure())

            $Private:Grid.AddHandler(
                [System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent,
                [System.Windows.Input.MouseButtonEventHandler] {
                    param(
                        $EventSender,
                        $EventArguments
                    )
                    try {
                        # A drag on a column divider is a resize, not a selection.
                        if ($EventArguments.OriginalSource -is [System.Windows.Controls.Primitives.Thumb]) {
                            return
                        }

                        $Private:VisualElement = $EventArguments.OriginalSource
                        $Private:ColumnHeader = $null
                        while ($null -ne $Private:VisualElement) {
                            if ($Private:VisualElement -is [System.Windows.Controls.Primitives.DataGridColumnHeader]) {
                                $Private:ColumnHeader = $Private:VisualElement
                                break
                            }
                            $Private:VisualElement = [System.Windows.Media.VisualTreeHelper]::GetParent($Private:VisualElement)
                        }

                        if ($null -eq $Private:ColumnHeader -or $null -eq $Private:ColumnHeader.Column) {
                            return
                        }

                        Set-FocusedQueryResult -Index $GridIndex

                        $Private:ControlPressed = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)
                        $Private:ShiftPressed = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)

                        # $EventSender, not a captured grid: the handler acts on the grid that raised
                        # the event, which is the one whose header was clicked.
                        Select-DataGridColumnCells -DataGrid $EventSender -Column $Private:ColumnHeader.Column -ControlPressed $Private:ControlPressed -ShiftPressed $Private:ShiftPressed
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                    }
                }.GetNewClosure()
            )

            $Private:Grid.Add_AutoGeneratingColumn({
                    param(
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

            $Private:Grid.Add_LoadingRow({
                    param(
                        $EventArguments
                    )
                    try {
                        $EventArguments.Row.Header = ($EventArguments.Row.GetIndex() + 1).ToString()
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                    }
                })
        }
    }
    catch {
        # A grid without its handlers still shows its rows. Losing the shortcuts is bad; losing the
        # whole completion because wiring them threw would be worse.
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
