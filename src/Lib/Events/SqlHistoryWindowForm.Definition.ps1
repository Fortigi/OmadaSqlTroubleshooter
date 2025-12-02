$Script:SqlHistoryWindowForm.Definition.Add_Loaded({
        $_ | Show-EventInfo

        $Script:MainWindowForm.Elements.ButtonShowHistory.IsEnabled = $false

        Invoke-LoadSqlHistoryData

        # #$Script:SqlHistoryWindowForm.PositionManager.Synchronizing = $true
        # $Script:SqlHistoryWindowForm.Definition.Dispatcher.Invoke({
        #         $Script:SqlHistoryWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top)

        #         "MainWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG

        #         $Script:SqlHistoryWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlHistoryWindowForm.Definition.Width)

        #         "SqlHistoryWindowForm Left: {0}" -f $Script:SqlHistoryWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG

        #         $Script:SqlHistoryWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:SqlHistoryWindowForm.Definition.Top)

        #         $Script:SqlHistoryWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlHistoryWindowForm.Definition.Left)

        #         "PositionManagerSqlHistoryWindow PositionOffSetLeft: {0}" -f $Script:SqlHistoryWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
        #         if ($null -ne ($Script:SqlHistoryWindowForm.Definition | Get-WindowSizeConfig)) {
        #             $Size = $Script:SqlHistoryWindowForm.Definition | Get-WindowSizeConfig

        #             "Sql Schema window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
        #             $Script:SqlHistoryWindowForm.Definition.Width = $Size.Split("x")[0]
        #             $Script:SqlHistoryWindowForm.Definition.Height = $Size.Split("x")[1]

        #             "SqlHistoryWindowForm Height: {0}" -f $Script:SqlHistoryWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
        #         }
        #         $Script:SqlHistoryWindowForm.PositionManager.Synchronizing = $false
        #     }, [System.Windows.Threading.DispatcherPriority]::Render)

        # $Script:MainWindowForm.Elements.ButtonShowHistory.IsEnabled = $false
        # $Script:SqlHistoryWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:SqlHistoryWindowForm.Definition.Top)

        # "PositionManagerSqlHistoryWindow PositionOffSetLeft: {0}" -f $Script:SqlHistoryWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
        # $Script:SqlHistoryWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlHistoryWindowForm.Definition.Left)

        # "PositionManagerSqlHistoryWindow PositionOffSetTop: {0}" -f $Script:SqlHistoryWindowForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG

        # "SqlHistoryWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:SqlHistoryWindowForm.Definition.Left, $Script:SqlHistoryWindowForm.Definition.Top, $Script:SqlHistoryWindowForm.Definition.Width , $Script:SqlHistoryWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
        $Script:SqlHistoryWindowForm.State = "Open"
        Restore-MainWindowFocus
    })

$Script:SqlHistoryWindowForm.Definition.Add_Closing({
        $_ | Show-EventInfo
        Save-WindowMeasurements
        $Script:SqlHistoryWindowForm.State = "Closing"
        if ($Script:MainWindowForm.State -eq "Open") {
            $false | Set-ConfigProperty -Property "SqlHistoryWindowFormOpen"
        }
    })

$Script:SqlHistoryWindowForm.Definition.Add_Closed({
        $_ | Show-EventInfo
        $Script:SqlHistoryWindowForm.State = "Closed"
        $Script:MainWindowForm.Elements.ButtonShowHistory.IsEnabled = $true
        Restore-MainWindowFocus
    })
