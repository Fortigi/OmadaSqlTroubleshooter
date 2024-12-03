function Update-LogWindowPosition {

    try {
        $Script:PositionManager.MainWindowRight = $Script:MainWindowForm.Definition.Left + $Script:MainWindowForm.Definition.Width
        $Script:PositionManager.MainWindowBottom = $Script:MainWindowForm.Definition.Top - $Script:MainWindowForm.Definition.Height
        $Script:PositionManager.ChildWindowRight = $Script:LogWindowForm.Definition.Left + $Script:LogWindowForm.Definition.Width
        $Script:PositionManager.ChildWindowBottom = $Script:LogWindowForm.Definition.Top - $Script:LogWindowForm.Definition.Height

        if ($Script:LogWindowForm.Definition.Left -lt $Script:MainWindowForm.Definition.Left) {
            $Script:LogWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left + $Script:MainWindowForm.Definition.Width
        }
        elseif ($Script:PositionManager.ChildWindowRight -gt $Script:PositionManager.MainWindowRight) {
            $Script:LogWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left - $Script:LogWindowForm.Definition.Width
        }

        if ($Script:LogWindowForm.Definition.Top -lt $Script:MainWindowForm.Definition.Top) {
            $Script:LogWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top + $Script:MainWindowForm.Definition.Height
        }
        elseif ($Script:PositionManager.ChildWindowBottom -gt $MainWindowBottom) {
            $Script:LogWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top - $Script:LogWindowForm.Definition.Height
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
