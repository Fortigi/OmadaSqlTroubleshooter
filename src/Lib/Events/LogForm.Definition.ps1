$Script:LogForm.Definition.Add_Loaded({
        $_ | Show-EventInfo
        $Script:LogForm.PositionManager.Synchronizing = $true
        $Script:LogForm.Definition.Dispatcher.Invoke({
                "MainFormForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainFormForm.Definition.Left, $Script:MainFormForm.Definition.Top, $Script:MainFormForm.Definition.Width , $Script:MainFormForm.Definition.Height | Write-LogOutput -LogType DEBUG
                $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top)
                "LogForm Top: {0}" -f $Script:LogForm.Definition.Top | Write-LogOutput -LogType DEBUG
                $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) + [Int]::Abs($Script:MainFormForm.Definition.Width)
                "LogForm Left: {0}" -f $Script:LogForm.Definition.Left | Write-LogOutput -LogType DEBUG
                $Script:LogForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogForm.Definition.Left) - [Int]::Abs($Script:MainFormForm.Definition.Left)
                "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:LogForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                $Script:LogForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:MainFormForm.Definition.Top)
                "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:LogForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG
                if ($null -ne ($Script:LogForm.Definition | Get-WindowSizeConfig)) {
                    $Size = $Script:LogForm.Definition | Get-WindowSizeConfig
                    "Log window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                    $Script:LogForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                    "LogForm Width: {0}" -f $Script:LogForm.Definition.Width | Write-LogOutput -LogType DEBUG
                    $Script:LogForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
                    "LogForm Height: {0}" -f $Script:LogForm.Definition.Height | Write-LogOutput -LogType DEBUG
                }
                $Script:LogForm.PositionManager.Synchronizing = $false
            }, [System.Windows.Threading.DispatcherPriority]::Render)
        $Script:MainFormForm.Elements.ButtonShowLog.IsEnabled = $false
        $Script:TextBoxLog.Text = $Script:RunTimeConfig.Logging.AppLogObject
        $Script:LogForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogForm.Definition.Left) - [Int]::Abs($Script:MainFormForm.Definition.Left)
        "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:LogForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:MainFormForm.Definition.Top)
        "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:LogForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG
        "LogForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height | Write-LogOutput -LogType DEBUG
        $Script:LogForm.State = "Open"
        Restore-MainFormFocus
    })

$Script:LogForm.Definition.Add_Closing({
        $_ | Show-EventInfo
        $Script:LogForm.State = "Closing"
        Save-WindowMeasurements
        if ($Script:MainFormForm.State -eq "Open") {
            $false | Set-ConfigProperty -Property "LogFormOpen"
        }
    })

$Script:LogForm.Definition.Add_Closed({
        $_ | Show-EventInfo
        $Script:LogForm.State = "Closed"
        $Script:MainFormForm.Elements.ButtonShowLog.IsEnabled = $true
        Restore-MainFormFocus
    })

$Script:LogForm.Definition.Add_LocationChanged({
        $_ | Show-EventInfo -LogType VERBOSE2
        if (!$Script:LogForm.PositionManager.Synchronizing) {
            $Script:LogForm.PositionManager.Synchronizing = $true
            "MainFormForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainFormForm.Definition.Left, $Script:MainFormForm.Definition.Top, $Script:MainFormForm.Definition.Width , $Script:MainFormForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
            "LogForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
            $Script:LogForm.Definition.Dispatcher.Invoke({
                    $_ | Show-EventInfo -LogType VERBOSE2
                    $Script:LogForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogForm.Definition.Left) - [Int]::Abs($Script:MainFormForm.Definition.Left)
                    "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:LogForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType VERBOSE2
                    $Script:LogForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:MainFormForm.Definition.Top)
                    "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:LogForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType VERBOSE2
                    $Script:LogForm.PositionManager.Synchronizing = $false
                }, [System.Windows.Threading.DispatcherPriority]::Render)
        }
    })

$Script:LogForm.Definition.Add_SizeChanged({
        $_ | Show-EventInfo -LogType VERBOSE2
        $Script:LogForm.Size = $Script:LogForm.Definition | Get-WindowSize
    })
