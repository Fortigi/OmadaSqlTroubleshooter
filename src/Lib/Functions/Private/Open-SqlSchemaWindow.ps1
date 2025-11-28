function Open-SqlSchemaWindow {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Sender', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Args', Justification = 'The use of the variable is on purpose')]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip show schema" | Write-LogOutput -LogType DEBUG
            $false | Set-ConfigProperty -Property "SqlSchemaWindowFormOpen"
            return
        }

        #Log window creation
        "Opening Sql Schema window" | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaWindowForm = New-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\SqlSchemaWindow.xaml") -ParentForm $Script:MainWindowForm.Definition
        [Int]$Script:SqlSchemaWindowForm.PositionManager.PositionOffSetRight = 405

        $true | Set-ConfigProperty -Property "SqlSchemaWindowFormOpen"

        $Script:SqlSchemaWindowForm.Definition.ShowInTaskbar = $false
        $Script:TreeViewSqlSchema = $Script:SqlSchemaWindowForm.Definition.FindName("TreeViewSqlSchema")

        $Script:TreeViewSqlSchema.Add_SelectedItemChanged({
                param ($Sender, $Args)
                $_ | Show-EventInfo
                Invoke-OnTreeViewItemShiftClick -sender $Sender -args $Args
            })

        # $Script:SqlSchemaWindowForm.Definition.Add_LostFocus({
        #         if ($null -ne $Script:TreeViewSqlSchema.SelectedItem) {
        #             $Script:TreeViewSqlSchema.SelectedItem.IsSelected = $false
        #         }
        #     })

        #region SqlSchemaWindowForm events

        $Script:SqlSchemaWindowForm.Definition.Add_LocationChanged({
                $_ | Show-EventInfo -LogType VERBOSE2
                if (!$Script:SqlSchemaWindowForm.PositionManager.Synchronizing) {
                    $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $true

                    "MainWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height | Write-LogOutput -LogType VERBOSE2

                    "SqlSchemaWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:SqlSchemaWindowForm.Definition.Left, $Script:SqlSchemaWindowForm.Definition.Top, $Script:SqlSchemaWindowForm.Definition.Width , $Script:SqlSchemaWindowForm.Definition.Height | Write-LogOutput -LogType VERBOSE2

                    $Script:SqlSchemaWindowForm.Definition.Dispatcher.Invoke({
                            $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Top)

                            "PositionManagerSqlSchemaWindow PositionOffSetLeft: {0}" -f $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType VERBOSE2
                            $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Left)

                            "PositionManagerSqlSchemaWindow PositionOffSetTop: {0}" -f $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType VERBOSE2

                            $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $false
                        }, [System.Windows.Threading.DispatcherPriority]::Render)
                }
            })

        $Script:SqlSchemaWindowForm.Definition.Add_SizeChanged({
                $_ | Show-EventInfo -LogType VERBOSE2
                $Script:SqlSchemaWindowForm.Size = $Script:SqlSchemaWindowForm.Definition | Get-WindowSize
            })

        #endregion

        if ($null -ne ($Script:SqlSchemaWindowForm.Definition | Get-WindowPositionConfig)) {
            $Position = $Script:SqlSchemaWindowForm.Definition | Get-WindowPositionConfig
            "Sql Schema window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:SqlSchemaWindowForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
            $Script:SqlSchemaWindowForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
        }

        #region SqlSchemaWindowForm events

        # $Script:SqlSchemaWindowForm.Definition.Add_Loaded({
        #         $_ | Show-EventInfo
        #         $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $true
        #         $Script:SqlSchemaWindowForm.Definition.Dispatcher.Invoke({
        #                 $Script:SqlSchemaWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top
        #                 $Script:SqlSchemaWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left - $Script:MainWindowForm.SqlSchemaWindowForm.Width
        #                 $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop = $Script:SqlSchemaWindowForm.Definition.Top - [Int]$MainWindowForm.Definition.Top
        #                 $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft = $Script:SqlSchemaWindowForm.Definition.Left + $Script:SqlSchemaWindowForm.Definition.Width + 2
        #                 if ($null -ne ($Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig)) {
        #                     $Size = $Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig
        #                     "Sql window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
        #                     $Script:SqlSchemaWindowForm.Definition.Width = [Int]$Size.Split("x")[0]
        #                     $Script:SqlSchemaWindowForm.Definition.Height = $Size.Split("x")[1]
        #                 }
        #                 $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $false
        #             }, [System.Windows.Threading.DispatcherPriority]::Render)
        #         $Script:MainWindowForm.Elements.ButtonShowSqlSchemaText | Set-ButtonText -Value "Hide S_ql Schema"
        #         [Int]$Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft = $Script:SqlSchemaWindowForm.Definition.Left + $Script:SqlSchemaWindowForm.Definition.Width + 2
        #         $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop = $Script:SqlSchemaWindowForm.Definition.Top - [Int]$MainWindowForm.Definition.Top
        #     })

        $Script:SqlSchemaWindowForm.Definition.Add_Loaded({
                $_ | Show-EventInfo

                Get-SqlSchemaObject

                $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $true
                $Script:SqlSchemaWindowForm.Definition.Dispatcher.Invoke({
                        $Script:SqlSchemaWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top)

                        "MainWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG

                        $Script:SqlSchemaWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Width)

                        "SqlSchemaWindowForm Left: {0}" -f $Script:SqlSchemaWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG

                        $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Top)

                        $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Left)

                        "PositionManagerSqlSchemaWindow PositionOffSetLeft: {0}" -f $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                        if ($null -ne ($Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig)) {
                            $Size = $Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig

                            "Sql Schema window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                            $Script:SqlSchemaWindowForm.Definition.Width = $Size.Split("x")[0]
                            $Script:SqlSchemaWindowForm.Definition.Height = $Size.Split("x")[1]

                            "SqlSchemaWindowForm Height: {0}" -f $Script:SqlSchemaWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
                        }
                        $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)

                $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonShowSqlSchemaText | Set-ButtonText -Value "Hide Schema"
                $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Top)

                "PositionManagerSqlSchemaWindow PositionOffSetLeft: {0}" -f $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaWindowForm.Definition.Left)

                "PositionManagerSqlSchemaWindow PositionOffSetTop: {0}" -f $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG

                "SqlSchemaWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:SqlSchemaWindowForm.Definition.Left, $Script:SqlSchemaWindowForm.Definition.Top, $Script:SqlSchemaWindowForm.Definition.Width , $Script:SqlSchemaWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
                $Script:SqlSchemaWindowForm.State = "Open"
            })

        $Script:SqlSchemaWindowForm.Definition.Add_Closing({
                $_ | Show-EventInfo
                Save-WindowMeasurements
                $Script:SqlSchemaWindowForm.State = "Closing"
                if ($Script:MainWindowForm.State -eq "Open") {
                    $false | Set-ConfigProperty -Property "SqlSchemaWindowFormOpen"
                }
            })

        $Script:SqlSchemaWindowForm.Definition.Add_Closed({
                $_ | Show-EventInfo
                $Script:SqlSchemaWindowForm.State = "Closed"
                $Script:MainWindowForm.Elements.ButtonShowSqlSchemaText | Set-ButtonText -Value "Schema"
            })

        #endregion
        $Script:SqlSchemaWindowForm.Definition.Show()

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
