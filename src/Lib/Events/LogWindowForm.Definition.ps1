$Script:LogWindowForm.Definition.Add_Loaded({
        $_ | Show-EventInfo
        $Script:LogWindowForm.PositionManager.Synchronizing = $true
        $Script:LogWindowForm.Definition.Dispatcher.Invoke({
                "MainWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
                $Script:LogWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top)
                "LogWindowForm Top: {0}" -f $Script:LogWindowForm.Definition.Top | Write-LogOutput -LogType DEBUG
                $Script:LogWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
                "LogWindowForm Left: {0}" -f $Script:LogWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG
                $Script:LogWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogWindowForm.Definition.Left) - [Int]::Abs($Script:MainWindowForm.Definition.Left)
                "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:LogWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                $Script:LogWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Top)
                "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:LogWindowForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG
                if ($null -ne ($Script:LogWindowForm.Definition | Get-WindowSizeConfig)) {
                    $Size = $Script:LogWindowForm.Definition | Get-WindowSizeConfig
                    "Log window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                    $Script:LogWindowForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                    "LogWindowForm Width: {0}" -f $Script:LogWindowForm.Definition.Width | Write-LogOutput -LogType DEBUG
                    $Script:LogWindowForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
                    "LogWindowForm Height: {0}" -f $Script:LogWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
                }
                $Script:LogWindowForm.PositionManager.Synchronizing = $false
            }, [System.Windows.Threading.DispatcherPriority]::Render)
        $Script:MainWindowForm.Elements.ButtonShowLog.IsEnabled = $false
        $Script:TextBoxLog.Text = $Script:RunTimeConfig.Logging.AppLogObject
        $Script:LogWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogWindowForm.Definition.Left) - [Int]::Abs($Script:MainWindowForm.Definition.Left)
        "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:LogWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Top)
        "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:LogWindowForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG
        "LogWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogWindowForm.Definition.Left, $Script:LogWindowForm.Definition.Top, $Script:LogWindowForm.Definition.Width , $Script:LogWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm.State = "Open"
        Restore-MainWindowFocus
    })

$Script:LogWindowForm.Definition.Add_Closing({
        $_ | Show-EventInfo
        $Script:LogWindowForm.State = "Closing"
        Save-WindowMeasurements
        if ($Script:MainWindowForm.State -eq "Open") {
            $false | Set-ConfigProperty -Property "LogWindowFormOpen"
        }
    })

$Script:LogWindowForm.Definition.Add_Closed({
        $_ | Show-EventInfo
        $Script:LogWindowForm.State = "Closed"
        $Script:MainWindowForm.Elements.ButtonShowLog.IsEnabled = $true
        Restore-MainWindowFocus
    })

$Script:LogWindowForm.Definition.Add_LocationChanged({
        $_ | Show-EventInfo -LogType VERBOSE2
        if (!$Script:LogWindowForm.PositionManager.Synchronizing) {
            $Script:LogWindowForm.PositionManager.Synchronizing = $true
            "MainWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
            "LogWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogWindowForm.Definition.Left, $Script:LogWindowForm.Definition.Top, $Script:LogWindowForm.Definition.Width , $Script:LogWindowForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
            $Script:LogWindowForm.Definition.Dispatcher.Invoke({
                    $_ | Show-EventInfo -LogType VERBOSE2
                    $Script:LogWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogWindowForm.Definition.Left) - [Int]::Abs($Script:MainWindowForm.Definition.Left)
                    "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:LogWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType VERBOSE2
                    $Script:LogWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Top)
                    "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:LogWindowForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType VERBOSE2
                    $Script:LogWindowForm.PositionManager.Synchronizing = $false
                }, [System.Windows.Threading.DispatcherPriority]::Render)
        }
    })

$Script:LogWindowForm.Definition.Add_SizeChanged({
        $_ | Show-EventInfo -LogType VERBOSE2
        $Script:LogWindowForm.Size = $Script:LogWindowForm.Definition | Get-WindowSize
    })
