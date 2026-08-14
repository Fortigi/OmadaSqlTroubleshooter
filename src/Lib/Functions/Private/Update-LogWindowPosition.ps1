function Update-LogFormPosition {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $Script:LogForm.PositionManager.MainFormRight = [Int]::Abs($Script:MainForm.Definition.Left) + [Int]::Abs($Script:MainForm.Definition.Width)
        "PositionManagerLogForm MainFormRight: {0}" -f $Script:LogForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.MainFormBottom = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:MainForm.Definition.Height)
        "PositionManagerLogForm MainFormBottom: {0}" -f $Script:LogForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.ChildFormRight = [Int]::Abs($Script:LogForm.Definition.Left) + [Int]::Abs($Script:LogForm.Definition.Width)
        "PositionManagerLogForm ChildFormRight: {0}" -f $Script:LogForm.PositionManager.ChildFormRight | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.ChildFormBottom = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:LogForm.Definition.Height)
        "PositionManagerLogForm ChildFormBottom: {0}" -f $Script:LogForm.PositionManager.ChildFormBottom | Write-LogOutput -LogType DEBUG

        if ([Int]::Abs($Script:LogForm.Definition.Left) -lt [Int]::Abs($Script:MainForm.Definition.Left)) {
            $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) + [Int]::Abs($Script:MainForm.Definition.Width)
            "LogForm Definition Left: {0}" -f $Script:LogForm.Definition.Left | Write-LogOutput -LogType DEBUG

        }
        elseif ($Script:LogForm.PositionManager.ChildFormRight -gt $Script:LogForm.PositionManager.MainFormRight) {
            $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) - $Script:LogForm.Definition.Width
            "LogForm Definition Left: {0}" -f $Script:LogForm.Definition.Left | Write-LogOutput -LogType DEBUG
        }

        if ($Script:LogForm.Definition.Top -lt [Int]::Abs($Script:MainForm.Definition.Top)) {
            $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) + [Int]::Abs($Script:MainForm.Definition.Height)
            "LogForm Definition Top: {0}" -f $Script:LogForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }
        elseif ($Script:PositionManager.ChildFormBottom -gt $MainFormBottom) {
            $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:LogForm.Definition.Height)
            "LogForm Definition Top: {0}" -f $Script:LogForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
