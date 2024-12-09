function Update-SqlSchemaWindowPosition {

    try {
        $Script:PositionManagerSqlSchemaWindow.MainWindowRight = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
        "PositionManagerSqlSchemaWindow MainWindowRight: {0}" -f $Script:PositionManagerSqlSchemaWindow.MainWindowRight | Write-LogOutput -LogType DEBUG
        $Script:PositionManagerSqlSchemaWindow.MainWindowBottom = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Height)
        "PositionManagerSqlSchemaWindow MainWindowBottom: {0}" -f $Script:PositionManagerSqlSchemaWindow.MainWindowRight | Write-LogOutput -LogType DEBUG
        $Script:PositionManagerSqlSchemaWindow.ChildWindowRight = [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Left) + [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Width)
        "PositionManagerSqlSchemaWindow ChildWindowRight: {0}" -f $Script:PositionManagerSqlSchemaWindow.ChildWindowRight | Write-LogOutput -LogType DEBUG
        $Script:PositionManagerSqlSchemaWindow.ChildWindowBottom = [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Height)
        "PositionManagerSqlSchemaWindow ChildWindowBottom: {0}" -f $Script:PositionManagerSqlSchemaWindow.ChildWindowBottom | Write-LogOutput -LogType DEBUG

        if ([Int]::Abs($Script:SqlSchemaWindowForm.Definition.Left) -lt [Int]::Abs($Script:MainWindowForm.Definition.Left)) {
            $Script:SqlSchemaWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
            "SqlSchemaWindowForm Definition Left: {0}" -f $Script:SqlSchemaWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG

        }
        elseif ($Script:PositionManagerSqlSchemaWindow.ChildWindowRight -gt $Script:PositionManagerSqlSchemaWindow.MainWindowRight) {
            $Script:SqlSchemaWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) - $Script:SqlSchemaWindowForm.Definition.Width
            "SqlSchemaWindowForm Definition Left: {0}" -f $Script:SqlSchemaWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG
        }

        if ($Script:SqlSchemaWindowForm.Definition.Top -lt [Int]::Abs($Script:MainWindowForm.Definition.Top)) {
            $Script:SqlSchemaWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top) + [Int]::Abs($Script:MainWindowForm.Definition.Height)
            "SqlSchemaWindowForm Definition Top: {0}" -f $Script:SqlSchemaWindowForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }
        elseif ($Script:PositionManager.ChildWindowBottom -gt $MainWindowBottom) {
            $Script:SqlSchemaWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Height)
            "SqlSchemaWindowForm Definition Top: {0}" -f $Script:SqlSchemaWindowForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
