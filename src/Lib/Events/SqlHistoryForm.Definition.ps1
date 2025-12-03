$Script:SqlHistoryForm.Definition.Add_Loaded({
        $_ | Show-EventInfo

        $Script:MainFormForm.Elements.ButtonShowHistory.IsEnabled = $false

        Invoke-LoadSqlHistoryData

        # #$Script:SqlHistoryForm.PositionManager.Synchronizing = $true
        # $Script:SqlHistoryForm.Definition.Dispatcher.Invoke({
        #         $Script:SqlHistoryForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top)

        #         "MainFormForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainFormForm.Definition.Left, $Script:MainFormForm.Definition.Top, $Script:MainFormForm.Definition.Width , $Script:MainFormForm.Definition.Height | Write-LogOutput -LogType DEBUG

        #         $Script:SqlHistoryForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) - [Int]::Abs($Script:SqlHistoryForm.Definition.Width)

        #         "SqlHistoryForm Left: {0}" -f $Script:SqlHistoryForm.Definition.Left | Write-LogOutput -LogType DEBUG

        #         $Script:SqlHistoryForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainFormForm.Definition.Top) - [Int]::Abs($Script:SqlHistoryForm.Definition.Top)

        #         $Script:SqlHistoryForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainFormForm.Definition.Left) - [Int]::Abs($Script:SqlHistoryForm.Definition.Left)

        #         "PositionManagerSqlHistoryWindow PositionOffSetLeft: {0}" -f $Script:SqlHistoryForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
        #         if ($null -ne ($Script:SqlHistoryForm.Definition | Get-WindowSizeConfig)) {
        #             $Size = $Script:SqlHistoryForm.Definition | Get-WindowSizeConfig

        #             "Sql Schema window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
        #             $Script:SqlHistoryForm.Definition.Width = $Size.Split("x")[0]
        #             $Script:SqlHistoryForm.Definition.Height = $Size.Split("x")[1]

        #             "SqlHistoryForm Height: {0}" -f $Script:SqlHistoryForm.Definition.Height | Write-LogOutput -LogType DEBUG
        #         }
        #         $Script:SqlHistoryForm.PositionManager.Synchronizing = $false
        #     }, [System.Windows.Threading.DispatcherPriority]::Render)

        # $Script:MainFormForm.Elements.ButtonShowHistory.IsEnabled = $false
        # $Script:SqlHistoryForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainFormForm.Definition.Top) - [Int]::Abs($Script:SqlHistoryForm.Definition.Top)

        # "PositionManagerSqlHistoryWindow PositionOffSetLeft: {0}" -f $Script:SqlHistoryForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
        # $Script:SqlHistoryForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainFormForm.Definition.Left) - [Int]::Abs($Script:SqlHistoryForm.Definition.Left)

        # "PositionManagerSqlHistoryWindow PositionOffSetTop: {0}" -f $Script:SqlHistoryForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG

        # "SqlHistoryForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:SqlHistoryForm.Definition.Left, $Script:SqlHistoryForm.Definition.Top, $Script:SqlHistoryForm.Definition.Width , $Script:SqlHistoryForm.Definition.Height | Write-LogOutput -LogType DEBUG
        $Script:SqlHistoryForm.State = "Open"
        Restore-MainFormFocus
    })

$Script:SqlHistoryForm.Definition.Add_Closing({
        $_ | Show-EventInfo
        Save-WindowMeasurements
        $Script:SqlHistoryForm.State = "Closing"
        if ($Script:MainFormForm.State -eq "Open") {
            $false | Set-ConfigProperty -Property "SqlHistoryFormOpen"
        }
    })

$Script:SqlHistoryForm.Definition.Add_Closed({
        $_ | Show-EventInfo
        $Script:SqlHistoryForm.State = "Closed"
        $Script:MainFormForm.Elements.ButtonShowHistory.IsEnabled = $true
        Restore-MainFormFocus
    })
