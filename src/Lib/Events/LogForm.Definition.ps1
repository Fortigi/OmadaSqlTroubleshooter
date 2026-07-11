$Script:LogForm.Definition.Add_Loaded({
        $_ | Show-EventInfo
        $Script:LogForm.PositionManager.Synchronizing = $true
        $Script:LogForm.Definition.Dispatcher.Invoke({
                "MainForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height | Write-LogOutput -LogType DEBUG
                $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top)
                "LogForm Top: {0}" -f $Script:LogForm.Definition.Top | Write-LogOutput -LogType DEBUG
                $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) + [Int]::Abs($Script:MainForm.Definition.Width)
                "LogForm Left: {0}" -f $Script:LogForm.Definition.Left | Write-LogOutput -LogType DEBUG
                $Script:LogForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogForm.Definition.Left) - [Int]::Abs($Script:MainForm.Definition.Left)
                "PositionManagerLogForm PositionOffSetLeft: {0}" -f $Script:LogForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                $Script:LogForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:MainForm.Definition.Top)
                "PositionManagerLogForm PositionOffSetTop: {0}" -f $Script:LogForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG
                if ($null -ne ($Script:LogForm.Definition | Get-FormSizeConfig)) {
                    $Size = $Script:LogForm.Definition | Get-FormSizeConfig
                    "Log Form size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                    $Script:LogForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                    "LogForm Width: {0}" -f $Script:LogForm.Definition.Width | Write-LogOutput -LogType DEBUG
                    $Script:LogForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
                    "LogForm Height: {0}" -f $Script:LogForm.Definition.Height | Write-LogOutput -LogType DEBUG
                }
                $Script:LogForm.PositionManager.Synchronizing = $false
            }, [System.Windows.Threading.DispatcherPriority]::Render)
        Set-ShowLogButtonEnabled -Enabled $false
        $Script:TextBoxLog.Text = $Script:RunTimeConfig.Logging.AppLogObject
        $Script:LogForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogForm.Definition.Left) - [Int]::Abs($Script:MainForm.Definition.Left)
        "PositionManagerLogForm PositionOffSetLeft: {0}" -f $Script:LogForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
        $Script:LogForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:MainForm.Definition.Top)
        "PositionManagerLogForm PositionOffSetTop: {0}" -f $Script:LogForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG
        "LogForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height | Write-LogOutput -LogType DEBUG
        $Script:LogForm.State = "Open"
        Restore-MainFormFocus
    })

$Script:LogForm.Definition.Add_Closing({
        $_ | Show-EventInfo
        $Script:LogForm.State = "Closing"
        Save-FormMeasurements
        if ($Script:MainForm.State -eq "Open") {
            $false | Set-ConfigProperty -Property "LogFormOpen"
        }
    })

$Script:LogForm.Definition.Add_Closed({
        $_ | Show-EventInfo
        $Script:LogForm.State = "Closed"
        Set-ShowLogButtonEnabled -Enabled $true
        Restore-MainFormFocus
    })

$Script:LogForm.Definition.Add_LocationChanged({
        $_ | Show-EventInfo -LogType VERBOSE2
        if (!$Script:LogForm.PositionManager.Synchronizing) {
            $Script:LogForm.PositionManager.Synchronizing = $true
            "MainForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
            "LogForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
            $Script:LogForm.Definition.Dispatcher.Invoke({
                    $_ | Show-EventInfo -LogType VERBOSE2
                    $Script:LogForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:LogForm.Definition.Left) - [Int]::Abs($Script:MainForm.Definition.Left)
                    "PositionManagerLogForm PositionOffSetLeft: {0}" -f $Script:LogForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType VERBOSE2
                    $Script:LogForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:LogForm.Definition.Top) - [Int]::Abs($Script:MainForm.Definition.Top)
                    "PositionManagerLogForm PositionOffSetTop: {0}" -f $Script:LogForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType VERBOSE2
                    $Script:LogForm.PositionManager.Synchronizing = $false
                }, [System.Windows.Threading.DispatcherPriority]::Render)
        }
    })

$Script:LogForm.Definition.Add_SizeChanged({
        $_ | Show-EventInfo -LogType VERBOSE2
        $Script:LogForm.Size = $Script:LogForm.Definition | Get-FormSize
    })
