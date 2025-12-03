function Update-LogWindowPosition {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $Script:LogForm.PositionManager.MainFormRight = [Int]::Abs($Script:MainFormForm.Definition.Left) + [Int]::Abs($Script:MainFormForm.Definition.Width)
        "PositionManagerLogWindow MainFormRight: {0}" -f $Script:LogForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.MainFormBottom = [Int]::Abs($Script:MainFormForm.Definition.Top) - [Int]::Abs($Script:MainFormForm.Definition.Height)
        "PositionManagerLogWindow MainFormBottom: {0}" -f $Script:LogForm.PositionManager.MainFormRight | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.ChildWindowRight = [Int]::Abs($Script:LogForm.Definition.Left) + [Int]::Abs($Script:LogForm.Definition.Width)
        "PositionManagerLogWindow ChildWindowRight: {0}" -f $Script:LogForm.PositionManager.ChildWindowRight | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.ChildWindowBottom = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:LogForm.Definition.Height)
        "PositionManagerLogWindow ChildWindowBottom: {0}" -f $Script:LogForm.PositionManager.ChildWindowBottom | Write-LogOutput -LogType DEBUG

        if ([Int]::Abs($Script:LogForm.Definition.Left) -lt [Int]::Abs($Script:MainFormForm.Definition.Left)) {
            $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) + [Int]::Abs($Script:MainFormForm.Definition.Width)
            "LogForm Definition Left: {0}" -f $Script:LogForm.Definition.Left | Write-LogOutput -LogType DEBUG

        }
        elseif ($Script:LogForm.PositionManager.ChildWindowRight -gt $Script:LogForm.PositionManager.MainFormRight) {
            $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) - $Script:LogForm.Definition.Width
            "LogForm Definition Left: {0}" -f $Script:LogForm.Definition.Left | Write-LogOutput -LogType DEBUG
        }

        if ($Script:LogForm.Definition.Top -lt [Int]::Abs($Script:MainFormForm.Definition.Top)) {
            $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top) + [Int]::Abs($Script:MainFormForm.Definition.Height)
            "LogForm Definition Top: {0}" -f $Script:LogForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }
        elseif ($Script:PositionManager.ChildWindowBottom -gt $MainFormBottom) {
            $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top) - [Int]::Abs($Script:LogForm.Definition.Height)
            "LogForm Definition Top: {0}" -f $Script:LogForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
