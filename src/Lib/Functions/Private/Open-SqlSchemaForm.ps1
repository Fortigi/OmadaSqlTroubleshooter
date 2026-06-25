function Open-SqlSchemaForm {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Sender', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'EventArgs', Justification = 'The use of the variable is on purpose')]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip show schema" | Write-LogOutput -LogType DEBUG
            $false | Set-ConfigProperty -Property "SqlSchemaFormOpen"
            return
        }

        #Log form creation
        "Opening Sql Schema form" | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\SqlSchemaForm.xaml") -ParentForm $Script:MainForm.Definition
        Import-EventObjects -ClassName "SqlSchemaForm"
        [Int]$Script:SqlSchemaForm.PositionManager.PositionOffSetRight = 405

        $true | Set-ConfigProperty -Property "SqlSchemaFormOpen"

        $Script:SqlSchemaForm.Definition.ShowInTaskbar = $false
        $Script:TreeViewSqlSchema = $Script:SqlSchemaForm.Definition.FindName("TreeViewSqlSchema")

        $Script:TreeViewSqlSchema.Add_SelectedItemChanged({
                param ($Sender, $EventArgs)
                $_ | Show-EventInfo
                Invoke-OnTreeViewItemShiftClick -Sender $Sender -EventArgs $EventArgs
            })

        # $Script:SqlSchemaForm.Definition.Add_LostFocus({
        #         if ($null -ne $Script:TreeViewSqlSchema.SelectedItem) {
        #             $Script:TreeViewSqlSchema.SelectedItem.IsSelected = $false
        #         }
        #     })

        #region SqlSchemaForm events

        $Script:SqlSchemaForm.Definition.Add_LocationChanged({
                $_ | Show-EventInfo -LogType VERBOSE2
                if (!$Script:SqlSchemaForm.PositionManager.Synchronizing) {
                    $Script:SqlSchemaForm.PositionManager.Synchronizing = $true

                    "MainForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height | Write-LogOutput -LogType VERBOSE2

                    "SqlSchemaForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width , $Script:SqlSchemaForm.Definition.Height | Write-LogOutput -LogType VERBOSE2

                    $Script:SqlSchemaForm.Definition.Dispatcher.Invoke({
                            $Script:SqlSchemaForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.Definition.Top)

                            "PositionManagerSqlSchemaForm PositionOffSetLeft: {0}" -f $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType VERBOSE2
                            $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaForm.Definition.Left)

                            "PositionManagerSqlSchemaForm PositionOffSetTop: {0}" -f $Script:SqlSchemaForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType VERBOSE2

                            $Script:SqlSchemaForm.PositionManager.Synchronizing = $false
                        }, [System.Windows.Threading.DispatcherPriority]::Render)
                }
            })

        $Script:SqlSchemaForm.Definition.Add_SizeChanged({
                $_ | Show-EventInfo -LogType VERBOSE2
                $Script:SqlSchemaForm.Size = $Script:SqlSchemaForm.Definition | Get-FormSize
            })

        #endregion

        if ($null -ne ($Script:SqlSchemaForm.Definition | Get-FormPositionConfig)) {
            $Position = $Script:SqlSchemaForm.Definition | Get-FormPositionConfig
            "Sql Schema form position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
            $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
        }
        if ($null -ne ($Script:SqlSchemaForm.Definition | Get-FormSizeConfig)) {
            $Size = $Script:SqlSchemaForm.Definition | Get-FormSizeConfig
            "Sql Schema form size (pre-show): {0}" -f $Size | Write-LogOutput -LogType DEBUG
            $Script:SqlSchemaForm.Definition.Width = [Int]$Size.Split("x")[0]
        }

        #region SqlSchemaForm events

        # $Script:SqlSchemaForm.Definition.Add_Loaded({
        #         $_ | Show-EventInfo
        #         $Script:SqlSchemaForm.PositionManager.Synchronizing = $true
        #         $Script:SqlSchemaForm.Definition.Dispatcher.Invoke({
        #                 $Script:SqlSchemaForm.Definition.Top = $Script:MainForm.Definition.Top
        #                 $Script:SqlSchemaForm.Definition.Left = $Script:MainForm.Definition.Left - $Script:MainForm.SqlSchemaForm.Width
        #                 $Script:SqlSchemaForm.PositionManager.PositionOffSetTop = $Script:SqlSchemaForm.Definition.Top - [Int]$MainForm.Definition.Top
        #                 $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft = $Script:SqlSchemaForm.Definition.Left + $Script:SqlSchemaForm.Definition.Width + 2
        #                 if ($null -ne ($Script:SqlSchemaForm.Definition | Get-FormSizeConfig)) {
        #                     $Size = $Script:SqlSchemaForm.Definition | Get-FormSizeConfig
        #                     "Sql window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
        #                     $Script:SqlSchemaForm.Definition.Width = [Int]$Size.Split("x")[0]
        #                     $Script:SqlSchemaForm.Definition.Height = $Size.Split("x")[1]
        #                 }
        #                 $Script:SqlSchemaForm.PositionManager.Synchronizing = $false
        #             }, [System.Windows.Threading.DispatcherPriority]::Render)
        #         $Script:MainForm.Elements.ButtonShowSqlSchemaText | Set-ButtonText -Value "Hide S_ql Schema"
        #         [Int]$Script:SqlSchemaForm.PositionManager.PositionOffSetLeft = $Script:SqlSchemaForm.Definition.Left + $Script:SqlSchemaForm.Definition.Width + 2
        #         $Script:SqlSchemaForm.PositionManager.PositionOffSetTop = $Script:SqlSchemaForm.Definition.Top - [Int]$MainForm.Definition.Top
        #     })

        $Script:SqlSchemaForm.Definition.Add_Loaded({
                $_ | Show-EventInfo

                Get-SqlSchemaObject

                $Script:SqlSchemaForm.PositionManager.Synchronizing = $true
                $Script:SqlSchemaForm.Definition.Dispatcher.Invoke({
                        $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top)

                        "MainForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height | Write-LogOutput -LogType DEBUG

                        $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaForm.Definition.Width)

                        "SqlSchemaForm Left: {0}" -f $Script:SqlSchemaForm.Definition.Left | Write-LogOutput -LogType DEBUG

                        $Script:SqlSchemaForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.Definition.Top)

                        $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaForm.Definition.Left)

                        "PositionManagerSqlSchemaForm PositionOffSetLeft: {0}" -f $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                        $Script:SqlSchemaForm.PositionManager.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)

                $Script:MainForm.Elements.ButtonShowSqlSchema.IsEnabled = $false
                $Script:SqlSchemaForm.PositionManager.PositionOffSetTop = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.Definition.Top)

                "PositionManagerSqlSchemaForm PositionOffSetLeft: {0}" -f $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft = [Int]::Abs($Script:MainForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaForm.Definition.Left)

                "PositionManagerSqlSchemaForm PositionOffSetTop: {0}" -f $Script:SqlSchemaForm.PositionManager.PositionOffSetTop | Write-LogOutput -LogType DEBUG

                "SqlSchemaForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width , $Script:SqlSchemaForm.Definition.Height | Write-LogOutput -LogType DEBUG
                $Script:SqlSchemaForm.State = "Open"
                $tv = $Script:TreeViewSqlSchema
                $Script:SqlSchemaForm.Definition.Dispatcher.Invoke(
                    {
                        if ($tv.Items.Count -gt 0) {
                            $firstSchema = $tv.Items[0]
                            if ($null -ne $firstSchema -and $firstSchema.Items.Count -gt 0) {
                                $firstTable = $firstSchema.Items[0]
                                $firstTable.IsExpanded = $true
                                $tv.UpdateLayout()
                                $firstTable.IsExpanded = $false
                            }
                        }
                    },
                    [System.Windows.Threading.DispatcherPriority]::Background
                )
                Restore-MainFormFocus
            })

        $Script:SqlSchemaForm.Definition.Add_Closing({
                $_ | Show-EventInfo
                Save-FormMeasurements
                $Script:SqlSchemaForm.State = "Closing"
                if ($Script:MainForm.State -eq "Open") {
                    $false | Set-ConfigProperty -Property "SqlSchemaFormOpen"
                }
            })

        $Script:SqlSchemaForm.Definition.Add_Closed({
                $_ | Show-EventInfo
                $Script:SqlSchemaForm.State = "Closed"
                $Script:MainForm.Elements.ButtonShowSqlSchema.IsEnabled = $true
                Restore-MainFormFocus
            })

        #endregion
        $Script:SqlSchemaForm.Definition.Show()

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
