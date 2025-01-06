function Update-LogWindowPosition {

    try {
        $Script:LogWindowForm.PositionManager.MainWindowRight = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
        "PositionManagerLogWindow MainWindowRight: {0}" -f $Script:LogWindowForm.PositionManager.MainWindowRight | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm.PositionManager.MainWindowBottom = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Height)
        "PositionManagerLogWindow MainWindowBottom: {0}" -f $Script:LogWindowForm.PositionManager.MainWindowRight | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm.PositionManager.ChildWindowRight = [Int]::Abs($Script:LogWindowForm.Definition.Left) + [Int]::Abs($Script:LogWindowForm.Definition.Width)
        "PositionManagerLogWindow ChildWindowRight: {0}" -f $Script:LogWindowForm.PositionManager.ChildWindowRight | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm.PositionManager.ChildWindowBottom = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:LogWindowForm.Definition.Height)
        "PositionManagerLogWindow ChildWindowBottom: {0}" -f $Script:LogWindowForm.PositionManager.ChildWindowBottom | Write-LogOutput -LogType DEBUG

        if ([Int]::Abs($Script:LogWindowForm.Definition.Left) -lt [Int]::Abs($Script:MainWindowForm.Definition.Left)) {
            $Script:LogWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
            "LogWindowForm Definition Left: {0}" -f $Script:LogWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG

        }
        elseif ($Script:LogWindowForm.PositionManager.ChildWindowRight -gt $Script:LogWindowForm.PositionManager.MainWindowRight) {
            $Script:LogWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) - $Script:LogWindowForm.Definition.Width
            "LogWindowForm Definition Left: {0}" -f $Script:LogWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG
        }

        if ($Script:LogWindowForm.Definition.Top -lt [Int]::Abs($Script:MainWindowForm.Definition.Top)) {
            $Script:LogWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top) + [Int]::Abs($Script:MainWindowForm.Definition.Height)
            "LogWindowForm Definition Top: {0}" -f $Script:LogWindowForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }
        elseif ($Script:PositionManager.ChildWindowBottom -gt $MainWindowBottom) {
            $Script:LogWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:LogWindowForm.Definition.Height)
            "LogWindowForm Definition Top: {0}" -f $Script:LogWindowForm.Definition.Top | Write-LogOutput -LogType DEBUG
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
