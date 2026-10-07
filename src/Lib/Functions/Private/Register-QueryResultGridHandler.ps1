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

            # Already wired - see IDEMPOTENT above. Tag is unused by this application's grids, so it
            # carries this feature's per-grid state: which result the grid is, and whether the user
            # has dragged its height.
            #
            # A HASHTABLE, not the bare index it started as. The sizing pass has to ask "did the user
            # size this one?" and an int cannot answer that - with Tag holding a plain index the
            # user-sized check could never fire and a dragged height would be overwritten on the next
            # pane resize.
            if ($Private:Grid.Tag -is [hashtable]) {
                continue
            }

            $Private:Grid.Tag = @{
                Index = $Private:Index
                # Set by the splitter's DragCompleted handler below, and cleared when
                # Set-TabQueryResult rebinds - so a drag survives pane resizes and the automatic
                # equal-share sizing resumes on the next execute.
                UserSized = $false
            }

            # PLAIN scriptblocks, every one of them - never .GetNewClosure() (issue #169). The rule is
            # the one MainForm.Definition.ps1 states for the whole application: a closure runs in a
            # detached dynamic module that resolves commands through the GLOBAL scope, so it cannot
            # see this module's private functions or its $Script: variables. In the installed module,
            # which exports three functions through the .psd1, every handler here threw
            # CommandNotFoundException on its first private call - and again on the Write-LogOutput in
            # its own catch, which is what reached the dispatcher safety net. Focus tracking, the
            # context menu, all four copy shortcuts, column selection and the resize handle were dead.
            #
            # Why it once looked otherwise (#166 measured "commands DO resolve from a closure"):
            # importing the .psm1 directly - development, and every test suite - exports EVERY
            # function, because it has no Export-ModuleMember. Global resolution then finds them. Only
            # the manifest import shows the failure; tests\_GridHandlerScopeProbe.ps1 reproduces it.
            #
            # The closures existed to give each handler the index of its own iteration. That index
            # already travels on the grid: the handlers read it from the SENDER's Tag, set above, so a
            # plain block gets the right grid without capturing anything.

            $Private:Grid.Add_GotFocus({
                    try {
                        # $args[0] is the sender - see the note above the key handler.
                        $Private:GridState = $args[0].Tag
                        if ($Private:GridState -isnot [hashtable]) {
                            return
                        }

                        Set-FocusedQueryResult -Index $Private:GridState.Index

                        # The column-selection anchor is single-grid state (Select-DataGridColumnCells
                        # keeps it in module scope). Moving focus to another result has to clear it, or
                        # a shift-click in the new grid would range-select from a column in the old one.
                        #
                        # Through a function rather than a `$Script:... = $null` written here (issue
                        # #166): the file that owns the state is the one that writes it.
                        Clear-DataGridColumnSelectionAnchor
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType DEBUG
                    }
                })

            $Private:Grid.Add_ContextMenuOpening({
                    try {
                        $Private:GridState = $args[0].Tag
                        if ($Private:GridState -isnot [hashtable]) {
                            return
                        }

                        # Opening the menu over a grid is itself a statement of which result the user
                        # means - they may never have clicked into it. Focus first, then let the menu
                        # decide what it may offer for that result.
                        Set-FocusedQueryResult -Index $Private:GridState.Index
                        Update-DataGridQueryResultContextMenuState
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType DEBUG
                    }
                })

            # The handlers in this file read $args[0] (the sender) and $args[1] (the event args)
            # instead of declaring parameters, and the reason is a binding trap rather than a style
            # preference.
            #
            # WPF invokes a handler with TWO arguments, (sender, eventArgs). With a single declared
            # parameter PowerShell binds the FIRST of them - the sender - to it, and the real event
            # args land in $args[1]. So `param($EventArguments)` silently handed each handler the
            # DataGrid: $EventArguments.Key never matched any key, and $EventArguments.Handled = $true
            # set a property on the grid instead of marking the event handled. That broke all four
            # copy shortcuts, the column header template and the row numbering, with nothing to show
            # it had happened.
            #
            # Declaring both parameters binds correctly but trips PSReviewUnusedParameter, which
            # src/lib/functions enables (src/lib/events, where these handlers used to live, excludes
            # it - which is why the originals could declare an unused $EventSender). Reading $args
            # satisfies both the binding and the rule.
            $Private:Grid.Add_PreviewKeyDown({
                    try {
                        $Private:GridState = $args[0].Tag
                        $EventArguments = $args[1]
                        if ($Private:GridState -isnot [hashtable]) {
                            return
                        }

                        Set-FocusedQueryResult -Index $Private:GridState.Index

                        $Private:ControlPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
                        $Private:ShiftPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift

                        # Copy-DataGridToClipboard directly, NOT the shared menu item's RaiseEvent
                        # (issue #166). Copy-DataGridToClipboard is exactly what each MenuItem's own
                        # Click handler calls, and it finds the grid itself through
                        # Get-FocusedQueryResultGrid, which the Set-FocusedQueryResult above has just
                        # pointed at this grid - so nothing is lost by not going through the menu, and
                        # the shortcuts do not depend on the $Script:DataGridQueryResultMenuItem*
                        # variables at all.
                        if ($EventArguments.Key -eq [System.Windows.Input.Key]::C -and $Private:ControlPressed -and $Private:ShiftPressed) {
                            "Ctrl+Shift+C key intercepted at DataGrid level - copying values with headers" | Write-LogOutput -LogType VERBOSE
                            Copy-DataGridToClipboard -IncludeHeader
                            $EventArguments.Handled = $true
                        }
                        elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::C -and $Private:ControlPressed -and -not $Private:ShiftPressed) {
                            "Ctrl+C key intercepted at DataGrid level - copying values only" | Write-LogOutput -LogType VERBOSE
                            Copy-DataGridToClipboard
                            $EventArguments.Handled = $true
                        }
                        elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::P -and $Private:ControlPressed -and $Private:ShiftPressed) {
                            "Ctrl+Shift+P key intercepted at DataGrid level - copying values only as PowerShell array" | Write-LogOutput -LogType VERBOSE
                            Copy-DataGridToClipboard -OutputFormat "PowerShellArray"
                            $EventArguments.Handled = $true
                        }
                        elseif ($EventArguments.Key -eq [System.Windows.Input.Key]::S -and $Private:ControlPressed -and $Private:ShiftPressed) {
                            "Ctrl+Shift+S key intercepted at DataGrid level - copying values only as Sql array" | Write-LogOutput -LogType VERBOSE
                            Copy-DataGridToClipboard -OutputFormat "SqlArray"
                            $EventArguments.Handled = $true
                        }
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                    }
                })

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

                        if ($EventSender.Tag -isnot [hashtable]) {
                            return
                        }

                        Set-FocusedQueryResult -Index $EventSender.Tag.Index

                        $Private:ControlPressed = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)
                        $Private:ShiftPressed = [bool]([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)

                        # $EventSender, not a captured grid: the handler acts on the grid that raised
                        # the event, which is the one whose header was clicked.
                        Select-DataGridColumnCells -DataGrid $EventSender -Column $Private:ColumnHeader.Column -ControlPressed $Private:ControlPressed -ShiftPressed $Private:ShiftPressed
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                    }
                }
            )

            $Private:Grid.Add_AutoGeneratingColumn({
                    try {
                        # $args[1], not a declared parameter - see the note above the key handler.
                        $EventArguments = $args[1]
                        $Private:HeaderTemplate = [System.Windows.Markup.XamlReader]::Parse(
                            '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding}" TextTrimming="CharacterEllipsis"/></DataTemplate>'
                        )
                        $EventArguments.Column.HeaderTemplate = $Private:HeaderTemplate
                    }
                    catch {
                        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                    }
                })

            # The ellipsis header template on the columns that ALREADY exist, for the same reason as
            # the row numbers below: AutoGeneratingColumn is a one-shot generation-time event, and by
            # the time these handlers attach the grid has already generated every column for the
            # result on screen. Without this the per-result grids lose the header trimming the single
            # grid had - a regression a reviewer caught after the row-number half was fixed.
            $Private:ColumnHeaderTemplate = [System.Windows.Markup.XamlReader]::Parse(
                '<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><TextBlock Text="{Binding}" TextTrimming="CharacterEllipsis"/></DataTemplate>'
            )
            foreach ($Private:ExistingColumn in @($Private:Grid.Columns)) {
                if ($null -eq $Private:ExistingColumn.HeaderTemplate) {
                    $Private:ExistingColumn.HeaderTemplate = $Private:ColumnHeaderTemplate
                }
            }

            # Row numbers on the rows that ALREADY exist. LoadingRow cannot do it on its own here:
            # these handlers attach from the deferred dispatcher callback, which can only find the
            # grids once a layout pass has realised their containers - and that same pass is what
            # loaded the rows. Measured in the STA probe: 6 realised rows, 0 headers set, because
            # LoadingRow had fired for every one of them before the handler existed.
            #
            # So the numbers are applied directly here, and the LoadingRow handler below stays for
            # the rows WPF realises later as the user scrolls a virtualised grid.
            for ($Private:RowIndex = 0; $Private:RowIndex -lt $Private:Grid.Items.Count; $Private:RowIndex++) {
                $Private:RealisedRow = $Private:Grid.ItemContainerGenerator.ContainerFromIndex($Private:RowIndex)
                if ($null -ne $Private:RealisedRow) {
                    $Private:RealisedRow.Header = ($Private:RowIndex + 1).ToString()
                }
            }

            # The result's resize handle (issue #151 feedback). The splitter is a SIBLING of the grid
            # in the item template, not a child of it, so it is found from the item container.
            #
            # The drag is applied to the grid's explicit Height rather than left to the splitter. The
            # template's rows are Auto - which is what lets the item size itself to header + grid +
            # splitter - and a GridSplitter cannot resize an Auto row. So DragCompleted reports the
            # total vertical change and that is added to the height the sizing pass had given it.
            $Private:SplitterQueue = [System.Collections.Generic.Queue[object]]::new()
            $Private:SplitterQueue.Enqueue($Private:Container)
            $Private:Splitter = $null
            while ($Private:SplitterQueue.Count -gt 0 -and $null -eq $Private:Splitter) {
                $Private:Node = $Private:SplitterQueue.Dequeue()
                $Private:ChildCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Private:Node)
                for ($Private:ChildIndex = 0; $Private:ChildIndex -lt $Private:ChildCount; $Private:ChildIndex++) {
                    $Private:Child = [System.Windows.Media.VisualTreeHelper]::GetChild($Private:Node, $Private:ChildIndex)
                    if ($Private:Child -is [System.Windows.Controls.GridSplitter]) {
                        $Private:Splitter = $Private:Child
                        break
                    }

                    $Private:SplitterQueue.Enqueue($Private:Child)
                }
            }

            if ($null -ne $Private:Splitter) {
                # The grid this splitter resizes, on the splitter's own Tag - the same move as the
                # grid's index above. The handlers below are plain scriptblocks and capture nothing,
                # and their sender is the SPLITTER, so this is how each one finds its grid.
                $Private:Splitter.Tag = $Private:Grid

                # LIVE, on DragDelta - so the grid's rows move with the handle instead of appearing
                # only when it is released. The markup pairs with this: ShowsPreview is False, because
                # a preview adorner is precisely the "drag a grey bar, see nothing until you let go"
                # behaviour this replaces.
                #
                # DragDelta's VerticalChange is the change since the LAST DragDelta, not since the
                # start of the drag, so it is applied incrementally to the current height. That is
                # also why DragCompleted below no longer applies anything: doing both would move the
                # grid twice as far as the handle.
                $Private:Splitter.Add_DragDelta({
                        try {
                            $Private:SplitterGrid = $args[0].Tag
                            $Private:DragArgs = $args[1]
                            if ($Private:SplitterGrid -isnot [System.Windows.Controls.DataGrid]) {
                                return
                            }

                            $Private:Wanted = [double]$Private:SplitterGrid.ActualHeight + [double]$Private:DragArgs.VerticalChange

                            # Never smaller than one row plus the header: a drag that collapses a
                            # result to nothing leaves the user with a grid they cannot grab again.
                            $Private:Minimum = Get-QueryResultGridFloor -DataGrid $Private:SplitterGrid -RowCount 1
                            if ($Private:Wanted -lt $Private:Minimum) {
                                $Private:Wanted = $Private:Minimum
                            }

                            $Private:SplitterGrid.Height = $Private:Wanted

                            # Marked on the first delta, not at the end: the sizing pass must already
                            # be leaving this grid alone while the drag is in progress, or a pane
                            # resize mid-drag would fight the handle.
                            if ($Private:SplitterGrid.Tag -is [hashtable]) {
                                $Private:SplitterGrid.Tag.UserSized = $true
                            }
                        }
                        catch {
                            $_.Exception.Message | Write-LogOutput -LogType DEBUG
                        }
                    })

                # The height is already applied by then - this only records what the user settled on.
                $Private:Splitter.Add_DragCompleted({
                        try {
                            $Private:SplitterGrid = $args[0].Tag
                            if ($Private:SplitterGrid -isnot [System.Windows.Controls.DataGrid]) {
                                return
                            }

                            if ($Private:SplitterGrid.Tag -is [hashtable]) {
                                $Private:SplitterGrid.Tag.UserSized = $true
                            }

                            "Result grid resized by the user to {0:n1}" -f [double]$Private:SplitterGrid.ActualHeight | Write-LogOutput -LogType VERBOSE
                        }
                        catch {
                            $_.Exception.Message | Write-LogOutput -LogType DEBUG
                        }
                    })
            }

            $Private:Grid.Add_LoadingRow({
                    try {
                        # $args[1], not a declared parameter - see the note above the key handler.
                        $EventArguments = $args[1]
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
