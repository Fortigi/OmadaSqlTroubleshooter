function Update-SqlSchemaFormPosition {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $Script:SqlSchemaForm.PositionManager.MainFormRight = [Int]::Abs($Script:MainFormForm.Definition.Left) + [Int]::Abs($Script:MainFormForm.Definition.Width)
        "PositionManagerSqlSchemaForm MainFormRight: {0}" -f $Script:SqlSchemaForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaForm.PositionManager.MainFormBottom = [Int]::Abs($Script:MainFormForm.Definition.Top) - [Int]::Abs($Script:MainFormForm.Definition.Height)
        "PositionManagerSqlSchemaForm MainFormBottom: {0}" -f $Script:SqlSchemaForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaForm.PositionManager.ChildWindowRight = [Int]::Abs($Script:SqlSchemaForm.Definition.Left) + [Int]::Abs($Script:SqlSchemaForm.Definition.Width)
        "PositionManagerSqlSchemaForm ChildWindowRight: {0}" -f $Script:SqlSchemaForm.PositionManager.ChildWindowRight | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaForm.PositionManager.ChildWindowBottom = [Int]::Abs($Script:SqlSchemaForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.Definition.Height)
        "PositionManagerSqlSchemaForm ChildWindowBottom: {0}" -f $Script:SqlSchemaForm.PositionManager.ChildWindowBottom | Write-LogOutput -LogType DEBUG

        if ([Int]::Abs($Script:SqlSchemaForm.Definition.Left) -lt [Int]::Abs($Script:MainFormForm.Definition.Left)) {
            $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) + [Int]::Abs($Script:MainFormForm.Definition.Width)
            "SqlSchemaForm Definition Left: {0}" -f $Script:SqlSchemaForm.Definition.Left | Write-LogOutput -LogType DEBUG

        }
        elseif ($Script:SqlSchemaForm.PositionManager.ChildWindowRight -gt $Script:SqlSchemaForm.PositionManager.MainFormRight) {
            $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) - $Script:SqlSchemaForm.Definition.Width
            "SqlSchemaForm Definition Left: {0}" -f $Script:SqlSchemaForm.Definition.Left | Write-LogOutput -LogType DEBUG
        }

        if ($Script:SqlSchemaForm.Definition.Top -lt [Int]::Abs($Script:MainFormForm.Definition.Top)) {
            $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top) + [Int]::Abs($Script:MainFormForm.Definition.Height)
            "SqlSchemaForm Definition Top: {0}" -f $Script:SqlSchemaForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }
        elseif ($Script:PositionManager.ChildWindowBottom -gt $MainFormBottom) {
            $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.Definition.Height)
            "SqlSchemaForm Definition Top: {0}" -f $Script:SqlSchemaForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
