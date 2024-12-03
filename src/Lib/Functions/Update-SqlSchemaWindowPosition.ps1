function Update-SqlSchemaWindowPosition {

    try {

        $Script:PositionManagerSqlSchemaWindow.MainWindowLeft = $Script:MainWindowForm.Definition.Left
        $Script:PositionManagerSqlSchemaWindow.MainWindowBottom = $Script:MainWindowForm.Definition.Top - $Script:MainWindowForm.Definition.Height
        $Script:PositionManagerSqlSchemaWindow.ChildWindowLeft = $Script:SqlSchemaWindowForm.Definition.Left - $Script:SqlSchemaWindowForm.Definition.Width - 5
        $Script:PositionManagerSqlSchemaWindow.ChildWindowBottom = $Script:SqlSchemaWindowForm.Definition.Top - $Script:SqlSchemaWindowForm.Definition.Height

        if ($Script:SqlSchemaWindowForm.Definition.Left -lt $Script:MainWindowForm.Definition.Left) {
            $Script:SqlSchemaWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left + $Script:SqlSchemaWindowForm.Definition.Width - 5
        }
        elseif ($Script:PositionManagerSqlSchemaWindow.ChildWindowLeft -gt $Script:PositionManagerSqlSchemaWindow.MainWindowLeft) {
            $Script:SqlSchemaWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left - $Script:SqlSchemaWindowForm.Definition.Width - 5
        }

        if ($Script:SqlSchemaWindowForm.Definition.Top -lt $Script:MainWindowForm.Definition.Top) {
            $Script:SqlSchemaWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top + $Script:MainWindowForm.Definition.Height
        }
        elseif ($Script:PositionManager.ChildWindowBottom -gt $MainWindowBottom) {
            $Script:SqlSchemaWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top - $Script:SqlSchemaWindowForm.Definition.Height
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
