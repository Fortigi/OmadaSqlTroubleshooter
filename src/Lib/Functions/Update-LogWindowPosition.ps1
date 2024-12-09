function Update-LogWindowPosition {

    try {
        $Script:PositionManagerLogWindow.MainWindowRight = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
        "PositionManagerLogWindow MainWindowRight: {0}" -f $Script:PositionManagerLogWindow.MainWindowRight | Write-LogOutput -LogType DEBUG
        $Script:PositionManagerLogWindow.MainWindowBottom = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Height)
        "PositionManagerLogWindow MainWindowBottom: {0}" -f $Script:PositionManagerLogWindow.MainWindowRight | Write-LogOutput -LogType DEBUG
        $Script:PositionManagerLogWindow.ChildWindowRight = [Int]::Abs($Script:LogWindowForm.Definition.Left) + [Int]::Abs($Script:LogWindowForm.Definition.Width)
        "PositionManagerLogWindow ChildWindowRight: {0}" -f $Script:PositionManagerLogWindow.ChildWindowRight | Write-LogOutput -LogType DEBUG
        $Script:PositionManagerLogWindow.ChildWindowBottom = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:LogWindowForm.Definition.Height)
        "PositionManagerLogWindow ChildWindowBottom: {0}" -f $Script:PositionManagerLogWindow.ChildWindowBottom | Write-LogOutput -LogType DEBUG

        if ([Int]::Abs($Script:LogWindowForm.Definition.Left) -lt [Int]::Abs($Script:MainWindowForm.Definition.Left)) {
            $Script:LogWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
            "LogWindowForm Definition Left: {0}" -f $Script:LogWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG

        }
        elseif ($Script:PositionManagerLogWindow.ChildWindowRight -gt $Script:PositionManagerLogWindow.MainWindowRight) {
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
