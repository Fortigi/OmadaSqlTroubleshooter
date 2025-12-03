function Update-SqlSchemaFormPosition {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $Script:SqlSchemaForm.PositionManager.MainFormRight = [Int]::Abs($Script:MainForm.Definition.Left) + [Int]::Abs($Script:MainForm.Definition.Width)
        "PositionManagerSqlSchemaForm MainFormRight: {0}" -f $Script:SqlSchemaForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaForm.PositionManager.MainFormBottom = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:MainForm.Definition.Height)
        "PositionManagerSqlSchemaForm MainFormBottom: {0}" -f $Script:SqlSchemaForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaForm.PositionManager.ChildFormRight = [Int]::Abs($Script:SqlSchemaForm.Definition.Left) + [Int]::Abs($Script:SqlSchemaForm.Definition.Width)
        "PositionManagerSqlSchemaForm ChildFormRight: {0}" -f $Script:SqlSchemaForm.PositionManager.ChildFormRight | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaForm.PositionManager.ChildFormBottom = [Int]::Abs($Script:SqlSchemaForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.Definition.Height)
        "PositionManagerSqlSchemaForm ChildFormBottom: {0}" -f $Script:SqlSchemaForm.PositionManager.ChildFormBottom | Write-LogOutput -LogType DEBUG

        if ([Int]::Abs($Script:SqlSchemaForm.Definition.Left) -lt [Int]::Abs($Script:MainForm.Definition.Left)) {
            $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) + [Int]::Abs($Script:MainForm.Definition.Width)
            "SqlSchemaForm Definition Left: {0}" -f $Script:SqlSchemaForm.Definition.Left | Write-LogOutput -LogType DEBUG

        }
        elseif ($Script:SqlSchemaForm.PositionManager.ChildFormRight -gt $Script:SqlSchemaForm.PositionManager.MainFormRight) {
            $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) - $Script:SqlSchemaForm.Definition.Width
            "SqlSchemaForm Definition Left: {0}" -f $Script:SqlSchemaForm.Definition.Left | Write-LogOutput -LogType DEBUG
        }

        if ($Script:SqlSchemaForm.Definition.Top -lt [Int]::Abs($Script:MainForm.Definition.Top)) {
            $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) + [Int]::Abs($Script:MainForm.Definition.Height)
            "SqlSchemaForm Definition Top: {0}" -f $Script:SqlSchemaForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }
        elseif ($Script:PositionManager.ChildFormBottom -gt $MainFormBottom) {
            $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.Definition.Height)
            "SqlSchemaForm Definition Top: {0}" -f $Script:SqlSchemaForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
