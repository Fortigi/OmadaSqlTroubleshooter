$Script:MainWindowForm.Definition.Add_LocationChanged({
    if (Test-LogWindowOpen -and -not $Script:PositionManagerLogWindow.Synchronizing) {
        $Script:PositionManagerLogWindow.Synchronizing = $true
        $Script:MainWindowForm.Definition.Dispatcher.Invoke({
                $Script:LogWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left + $Script:PositionManagerLogWindow.PositionOffSetLeft
                $Script:LogWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top + $Script:PositionManagerLogWindow.PositionOffSetTop
                $Script:PositionManagerLogWindow.Synchronizing = $false
            }, [System.Windows.Threading.DispatcherPriority]::Render)
    }
    if (Test-SqlSchemaWindowOpen -and -not $Script:PositionManagerSqlSchemaWindow.Synchronizing) {
        $Script:PositionManagerSqlSchemaWindow.Synchronizing = $true
        $Script:MainWindowForm.Definition.Dispatcher.Invoke({
                $Script:SqlSchemaWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left - $Script:PositionManagerSqlSchemaWindow.PositionOffSetLeft
                $Script:SqlSchemaWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top - $Script:PositionManagerSqlSchemaWindow.PositionOffSetTop
                $Script:PositionManagerSqlSchemaWindow.Synchronizing = $false
            }, [System.Windows.Threading.DispatcherPriority]::Render)
    }
})
