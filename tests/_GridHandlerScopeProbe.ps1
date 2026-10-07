#Requires -Version 7.0
# Issue #169. Runs the result-grid handlers the way the INSTALLED module runs them: from a module
# whose private functions are not visible in the global scope.
#
# That visibility is the whole bug. A handler closed with .GetNewClosure() runs in a detached dynamic
# module and resolves commands through the GLOBAL scope, not through this module. Importing the
# .psm1 directly - which is what development and the other test suites do - exports every function,
# so such a handler works there. The installed module is loaded through the .psd1, whose
# FunctionsToExport names three functions, and there every private call in a closure throws
# CommandNotFoundException - including the Write-LogOutput in the handler's own catch, which is the
# exception that reached the dispatcher.
#
# So the real Register-QueryResultGridHandler.ps1 is dot-sourced into a New-Module alongside
# recording stubs for its collaborators, and the module exports only the runner. Nothing else in this
# process can see a stub, exactly as nothing outside the installed module can see a private function.
#
# Run as `pwsh -STA -File _GridHandlerScopeProbe.ps1 -RepositoryRoot <root>`: WPF elements need an
# STA thread. Prints one JSON object and nothing else, for Register-QueryResultGridHandler.Tests.ps1.
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryRoot
)

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
}
catch {
    [pscustomobject]@{ Ok = $false; Error = ("WPF is not available: {0}" -f $_.Exception.Message) } | ConvertTo-Json -Compress
    return
}

$HandlerPath = Join-Path $RepositoryRoot "src\Lib\Functions\Private\Register-QueryResultGridHandler.ps1"

$ProbeModule = New-Module -Name GridHandlerScopeProbe -ArgumentList $HandlerPath -ScriptBlock {
    param(
        [string]$HandlerPath
    )

    . $HandlerPath

    # What the handlers reached, in order. A handler that could not resolve a command records nothing.
    $script:Recorded = [System.Collections.Generic.List[string]]::new()
    $script:Session = $null

    function Get-ActiveTabSession {
        return $script:Session
    }

    function Find-VisualChildDataGrid {
        param(
            $Parent
        )

        foreach ($Child in $Parent.Children) {
            if ($Child -is [System.Windows.Controls.DataGrid]) {
                return $Child
            }
        }

        return $null
    }

    function Set-FocusedQueryResult {
        param(
            $TabSession,
            [int]$Index
        )

        $script:Recorded.Add(("Focus:{0}" -f $Index))
    }

    function Clear-DataGridColumnSelectionAnchor {
        $script:Recorded.Add("ClearAnchor")
    }

    function Update-DataGridQueryResultContextMenuState {
        $script:Recorded.Add("MenuState")
    }

    function Copy-DataGridToClipboard {
        param(
            [switch]$IncludeHeader,
            [string]$OutputFormat = "Default"
        )

        $script:Recorded.Add(("Copy:{0}" -f $OutputFormat))
    }

    function Select-DataGridColumnCells {
        param(
            $DataGrid,
            $Column,
            $ControlPressed,
            $ShiftPressed
        )

        $script:Recorded.Add(("SelectColumn:{0}" -f $DataGrid.Tag.Index))
    }

    function Get-QueryResultGridFloor {
        param(
            $DataGrid,
            [int]$RowCount
        )

        $script:Recorded.Add("Floor")
        return 10.0
    }

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $InputObject,
            [string]$LogType,
            $ErrorObject
        )

        process {
            $script:Recorded.Add(("Log:{0}:{1}" -f $LogType, $InputObject))
        }
    }

    function Invoke-GridHandlerScopeProbe {
        # Two results, so a handler that reported the wrong grid's index - the failure the old
        # closures existed to prevent - is distinguishable from one that reported the right one.
        $Containers = @(
            foreach ($Position in 0..1) {
                $Container = [System.Windows.Controls.Grid]::new()
                [void]$Container.Children.Add([System.Windows.Controls.DataGrid]::new())
                [void]$Container.Children.Add([System.Windows.Controls.GridSplitter]::new())
                $Container
            }
        )

        $Generator = [pscustomobject]@{ Containers = $Containers }
        $Generator | Add-Member -MemberType ScriptMethod -Name ContainerFromIndex -Value {
            param($Index)
            return $this.Containers[$Index]
        }

        $script:Session = [pscustomobject]@{
            Elements = [pscustomobject]@{
                ItemsControlQueryResults = [pscustomobject]@{
                    Items                  = $Containers
                    ItemContainerGenerator = $Generator
                }
            }
        }

        Register-QueryResultGridHandler

        $Grid = $Containers[1].Children[0]
        $Splitter = $Containers[1].Children[1]
        $Escaped = [System.Collections.Generic.List[string]]::new()

        # Each event is raised on its own, so one handler that throws cannot hide whether the next
        # one works. An exception that escapes RaiseEvent is exactly what reached the dispatcher.
        $Raise = {
            param($Name, $Target, $EventArguments)

            try {
                $Target.RaiseEvent($EventArguments)
            }
            catch {
                $Escaped.Add(("{0}: {1}" -f $Name, $_.Exception.GetBaseException().Message))
            }
        }

        & $Raise "GotFocus" $Grid ([System.Windows.RoutedEventArgs]::new([System.Windows.UIElement]::GotFocusEvent))

        # ContextMenuEventArgs has no public constructor; the internal (source, opening) one is the
        # one WPF itself uses.
        $ContextMenuArguments = $null
        $ContextMenuConstructor = [System.Windows.Controls.ContextMenuEventArgs].GetConstructor(
            [System.Reflection.BindingFlags]'NonPublic, Instance', $null, [type[]]@([object], [bool]), $null
        )
        if ($null -ne $ContextMenuConstructor) {
            $ContextMenuArguments = $ContextMenuConstructor.Invoke(@($Grid, $true))
            $ContextMenuArguments.RoutedEvent = [System.Windows.FrameworkElement]::ContextMenuOpeningEvent
            & $Raise "ContextMenuOpening" $Grid $ContextMenuArguments
        }

        # A synthetic key arrives with no modifiers held (Keyboard.Modifiers reads the real keyboard),
        # so no copy branch runs. What this proves is that the handler reaches Set-FocusedQueryResult.
        $KeySource = [System.Windows.Interop.HwndSource]::new([System.Windows.Interop.HwndSourceParameters]::new("GridHandlerScopeProbe"))
        $KeyArguments = [System.Windows.Input.KeyEventArgs]::new([System.Windows.Input.Keyboard]::PrimaryDevice, $KeySource, 0, [System.Windows.Input.Key]::C)
        $KeyArguments.RoutedEvent = [System.Windows.Input.Keyboard]::PreviewKeyDownEvent
        & $Raise "PreviewKeyDown" $Grid $KeyArguments
        $KeySource.Dispose()

        # A column-header click. The handler walks up from OriginalSource to a DataGridColumnHeader
        # whose Column is set. Column is read-only and outside a laid-out grid nothing sets it, so its
        # private backing field is written. Source is assigned before raising so OriginalSource is the
        # header, and the event is raised on the grid because that is where the handler is attached.
        $ColumnHeaderClicked = $false
        $ColumnField = [System.Windows.Controls.Primitives.DataGridColumnHeader].GetField("_column", [System.Reflection.BindingFlags]'NonPublic, Instance')
        if ($null -ne $ColumnField) {
            $Header = [System.Windows.Controls.Primitives.DataGridColumnHeader]::new()
            $ColumnField.SetValue($Header, [System.Windows.Controls.DataGridTextColumn]::new())
            $MouseArguments = [System.Windows.Input.MouseButtonEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $MouseArguments.RoutedEvent = [System.Windows.UIElement]::PreviewMouseLeftButtonDownEvent
            $MouseArguments.Source = $Header
            & $Raise "PreviewMouseLeftButtonDown" $Grid $MouseArguments
            $ColumnHeaderClicked = $true
        }

        & $Raise "DragDelta" $Splitter ([System.Windows.Controls.Primitives.DragDeltaEventArgs]::new(0, 40))
        & $Raise "DragCompleted" $Splitter ([System.Windows.Controls.Primitives.DragCompletedEventArgs]::new(0, 40, $false))

        return [pscustomobject]@{
            Ok                    = $true
            ContextMenuRaised     = ($null -ne $ContextMenuArguments)
            ColumnHeaderClicked   = $ColumnHeaderClicked
            Recorded              = @($script:Recorded)
            Escaped               = @($Escaped)
            GridHeight            = $Grid.Height
            UserSized             = [bool]$Grid.Tag.UserSized
            OtherGridHeightIsAuto = [double]::IsNaN($Containers[0].Children[0].Height)
        }
    }

    Export-ModuleMember -Function Invoke-GridHandlerScopeProbe
}

try {
    $ProbeModule | Import-Module
    Invoke-GridHandlerScopeProbe | ConvertTo-Json -Compress -Depth 4
}
catch {
    [pscustomobject]@{ Ok = $false; Error = $_.Exception.Message } | ConvertTo-Json -Compress
}
