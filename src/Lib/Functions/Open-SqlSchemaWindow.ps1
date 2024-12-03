function Open-SqlSchemaWindow {
    try {
        #Log window creation
        "Opening Sql Schema window" | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaWindowForm = New-FormObject -FormPath (Join-Path $ScriptRootFolder -ChildPath "lib\ui\SqlSchemaWindow.xaml")
        $true | Invoke-ProcessConfigSettings -Property "SqlSchemaWindowFormOpen"

        $Script:SqlSchemaWindowForm.Definition.Owner = $Script:MainWindowForm.Definition
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
                if (!$Script:PositionManagerSqlSchemaWindow.Synchronizing) {
                    $Script:PositionManagerSqlSchemaWindow.Synchronizing = $true
                    $Script:SqlSchemaWindowForm.Definition.Dispatcher.Invoke({
                            $Script:PositionManagerSqlSchemaWindow.PositionOffSetTop = $Script:MainWindowForm.Definition.Top - $Script:SqlSchemaWindowForm.Definition.Top
                            $Script:PositionManagerSqlSchemaWindow.PositionOffSetLeft = $Script:MainWindowForm.Definition.Left - $Script:SqlSchemaWindowForm.Definition.Left
                            $Script:PositionManagerSqlSchemaWindow.Synchronizing = $false
                        }, [System.Windows.Threading.DispatcherPriority]::Render)
                }
            })

        $Script:SqlSchemaWindowForm.Definition.Add_SizeChanged({
                $Script:SqlSchemaWindowForm.Size = $Script:SqlSchemaWindowForm.Definition | Get-WindowSize
            })

        #endregion

        if ($null -ne ($Script:SqlSchemaWindowForm.Definition | Get-WindowPositionConfig)) {
            $Position = $Script:SqlSchemaWindowForm.Definition | Get-WindowPositionConfig
            "Sql Schema window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:SqlSchemaWindowForm.Definition.Left = [double]$Position.Split("x")[0]
            $Script:SqlSchemaWindowForm.Definition.Top = [double]$Position.Split("x")[1]
        }

        #region SqlSchemaWindowForm events

        # $Script:SqlSchemaWindowForm.Definition.Add_Loaded({
        #         $_ | Show-EventInfo
        #         $Script:PositionManagerSqlSchemaWindow.Synchronizing = $true
        #         $Script:SqlSchemaWindowForm.Definition.Dispatcher.Invoke({
        #                 $Script:SqlSchemaWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top
        #                 $Script:SqlSchemaWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left - $Script:MainWindowForm.SqlSchemaWindowForm.Width - 5
        #                 $Script:PositionManagerSqlSchemaWindow.PositionOffSetTop = $Script:SqlSchemaWindowForm.Definition.Top - $Script:MainWindowForm.Definition.Top
        #                 $Script:PositionManagerSqlSchemaWindow.PositionOffSetLeft = $Script:SqlSchemaWindowForm.Definition.Left + $Script:SqlSchemaWindowForm.Definition.Width + 5
        #                 if ($null -ne ($Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig)) {
        #                     $Size = $Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig
        #                     "Sql window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
        #                     $Script:SqlSchemaWindowForm.Definition.Width = [double]$Size.Split("x")[0]
        #                     $Script:SqlSchemaWindowForm.Definition.Height = [double]$Size.Split("x")[1]
        #                 }
        #                 $Script:PositionManagerSqlSchemaWindow.Synchronizing = $false
        #             }, [System.Windows.Threading.DispatcherPriority]::Render)
        #         $Script:MainWindowForm.Elements.ButtonShowSqlSchema.Content = "Hide S_ql Schema"
        #         $Script:PositionManagerSqlSchemaWindow.PositionOffSetLeft = $Script:SqlSchemaWindowForm.Definition.Left + $Script:SqlSchemaWindowForm.Definition.Width + 5
        #         $Script:PositionManagerSqlSchemaWindow.PositionOffSetTop = $Script:SqlSchemaWindowForm.Definition.Top - $Script:MainWindowForm.Definition.Top
        #     })

        $Script:SqlSchemaWindowForm.Definition.Add_Loaded({
                $_ | Show-EventInfo

                Get-SqlSchemaObject

                $Script:PositionManagerSqlSchemaWindow.Synchronizing = $true
                $Script:SqlSchemaWindowForm.Definition.Dispatcher.Invoke({
                        $Script:SqlSchemaWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top
                        $Script:SqlSchemaWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left - $Script:SqlSchemaWindowForm.Definition.Width - 5
                        $Script:PositionManagerSqlSchemaWindow.PositionOffSetTop = $Script:MainWindowForm.Definition.Top - $Script:SqlSchemaWindowForm.Definition.Top
                        $Script:PositionManagerSqlSchemaWindow.PositionOffSetLeft = $Script:MainWindowForm.Definition.Left - $Script:SqlSchemaWindowForm.Definition.Left
                        if ($null -ne ($Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig)) {
                            $Size = $Script:SqlSchemaWindowForm.Definition | Get-WindowSizeConfig
                            "Sql Schema window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                            $Script:SqlSchemaWindowForm.Definition.Width = [double]$Size.Split("x")[0]
                            $Script:SqlSchemaWindowForm.Definition.Height = [double]$Size.Split("x")[1]
                        }
                        $Script:PositionManagerSqlSchemaWindow.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)
                $Script:MainWindowForm.Elements.ButtonShowSqlSchema.Content = "Hide S_ql Schema"
                $Script:PositionManagerSqlSchemaWindow.PositionOffSetTop = $Script:MainWindowForm.Definition.Top - $Script:SqlSchemaWindowForm.Definition.Top
                $Script:PositionManagerSqlSchemaWindow.PositionOffSetLeft = $Script:MainWindowForm.Definition.Left - $Script:SqlSchemaWindowForm.Definition.Left

            })

        $Script:SqlSchemaWindowForm.Definition.Add_Closing({
                $_ | Show-EventInfo
                Save-WindowMeasurements
                $false | Invoke-ProcessConfigSettings -Property "SqlSchemaWindowFormOpen"
            })

        $Script:SqlSchemaWindowForm.Definition.Add_Closed({
                $_ | Show-EventInfo
                $Script:MainWindowForm.Elements.ButtonShowSqlSchema.Content = "Show S_ql Schema"
            })

        #endregion
        $Script:SqlSchemaWindowForm.Definition.Show()

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
