function Open-LogWindow {
    try {
        #Log window creation
        "Opening Log window" | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm = New-FormObject -FormPath (Join-Path $ScriptRootFolder -ChildPath "lib\ui\LogWindow.xaml")
        $true | Invoke-ProcessConfigSettings -Property "LogWindowFormOpen"
        $Script:LogWindowForm.Definition.Owner = $Script:MainWindowForm.Definition
        $Script:LogWindowForm.Definition.ShowInTaskbar = $false
        $Script:TextBoxLog = $Script:LogWindowForm.Definition.FindName("TextBoxLog")

        #Set log level to show
        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.LogLevel)) {
            if (($LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Measure-Object).count -le 0 -and !$LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Content.Contains($Script:AppConfig.LogLevel)) {
                $ComboBoxSelectLogLevelItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectLogLevelItem.Content = $Script:AppConfig.LogLevel
                $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Add($ComboBoxSelectLogLevelItem) | Out-Null
            }
            $LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedValue = $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Where-Object { $_.Content -eq $Script:AppConfig.LogLevel }
            $Script:LogLevelSetting = $Script:AppConfig.LogLevel
        }
        else {
            if (($LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Measure-Object).count -le 0 -and !$LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Content.Contains("INFO")) {
                $ComboBoxSelectLogLevelItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectLogLevelItem.Content = "INFO"
                $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Add($ComboBoxSelectLogLevelItem) | Out-Null
            }
            $LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedValue = $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Where-Object { $_.Content -eq "INFO" }
            $Script:LogLevelSetting = $LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedValue.Content
        }

        #region LogWindowForm events

        $Script:LogWindowForm.Definition.Add_LocationChanged({
                if (!$Script:PositionManagerLogWindow.Synchronizing) {
                    $Script:PositionManagerLogWindow.Synchronizing = $true
                    $Script:LogWindowForm.Definition.Dispatcher.Invoke({
                            $Script:PositionManagerLogWindow.PositionOffSetTop = $Script:LogWindowForm.Definition.Top - $Script:MainWindowForm.Definition.Top
                            $Script:PositionManagerLogWindow.PositionOffSetLeft = $Script:LogWindowForm.Definition.Left - $Script:MainWindowForm.Definition.Left
                            $Script:PositionManagerLogWindow.Synchronizing = $false
                        }, [System.Windows.Threading.DispatcherPriority]::Render)
                }
            })

        $Script:LogWindowForm.Definition.Add_SizeChanged({
                $Script:LogWindowForm.Size = $Script:LogWindowForm.Definition | Get-WindowSize
            })

        #endregion

        if ($null -ne ($Script:LogWindowForm.Definition | Get-WindowPositionConfig)) {
            $Position = $Script:LogWindowForm.Definition | Get-WindowPositionConfig
            "Log window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:LogWindowForm.Definition.Left = [double]$Position.Split("x")[0]
            $Script:LogWindowForm.Definition.Top = [double]$Position.Split("x")[1]
        }

        #region LogWindowForm events
        $Script:LogWindowForm.Definition.Add_Loaded({
                $_ | Show-EventInfo
                $Script:PositionManagerLogWindow.Synchronizing = $true
                $Script:LogWindowForm.Definition.Dispatcher.Invoke({
                        $Script:LogWindowForm.Definition.Top = $Script:MainWindowForm.Definition.Top
                        $Script:LogWindowForm.Definition.Left = $Script:MainWindowForm.Definition.Left + $Script:MainWindowForm.Definition.Width + 5
                        $Script:PositionManagerLogWindow.PositionOffSetTop = $Script:LogWindowForm.Definition.Top - $Script:MainWindowForm.Definition.Top
                        $Script:PositionManagerLogWindow.PositionOffSetLeft = $Script:LogWindowForm.Definition.Left - $Script:MainWindowForm.Definition.Left
                        if ($null -ne ($Script:LogWindowForm.Definition | Get-WindowSizeConfig)) {
                            $Size = $Script:LogWindowForm.Definition | Get-WindowSizeConfig
                            "Log window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                            $Script:LogWindowForm.Definition.Width = [double]$Size.Split("x")[0]
                            $Script:LogWindowForm.Definition.Height = [double]$Size.Split("x")[1]
                        }
                        $Script:PositionManagerLogWindow.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)
                $Script:MainWindowForm.Elements.ButtonShowLog.Content = "_Hide Log"
                $Script:TextBoxLog.Text = $AppLogObject
                $Script:PositionManagerLogWindow.PositionOffSetLeft = $Script:LogWindowForm.Definition.Left - $Script:MainWindowForm.Definition.Left
                $Script:PositionManagerLogWindow.PositionOffSetTop = $Script:LogWindowForm.Definition.Top - $Script:MainWindowForm.Definition.Top
            })

        $Script:LogWindowForm.Definition.Add_Closing({
                $_ | Show-EventInfo
                Save-WindowMeasurements
                $false | Invoke-ProcessConfigSettings -Property "LogWindowFormOpen"
            })

        $Script:LogWindowForm.Definition.Add_Closed({
                $_ | Show-EventInfo
                $Script:MainWindowForm.Elements.ButtonShowLog.Content = "_Show Log"
            })

        $Script:LogWindowForm.Elements.ButtonClearLog.Add_Click({
                $_ | Show-EventInfo
                $Script:TextBoxLog.Clear()
                "Log cleared" | Write-LogOutput
            })

        $Script:TextBoxLog.remove_TextChanged({
                $_ | Show-EventInfo
                $AppLogObject.Clear()
            })

        $Script:LogWindowForm.Elements.ButtonExportLogFile.Add_Click({
                $_ | Show-EventInfo

                $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
                $SaveFileDialog.Filter = "Log files (*.log) | *.log | All files (*.*) | *.*"
                $SaveFileDialog.Title = "Save Log File"
                $SaveFileDialog.FileName = "OmadaTroubleshooter.log"
                if ($SaveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    if ($Null -eq $SaveFileDialog.FileName) {
                        return
                    }
                    else {
                        $AppLogObject | Set-Content $SaveFileDialog.FileName -Encoding UTF8
                    }
                }
                else {
                    "File was not saved!" | Write-LogOutput -LogType DEBUG
                }
            })

        $Script:LogWindowForm.Elements.ComboBoxSelectLogLevel.Add_SelectionChanged({
                $_ | Show-EventInfo
                $Script:LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content | Invoke-ProcessConfigSettings -Property "LogLevel"
                $Script:LogLevelSetting = $Script:LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content
                "Logging set to {0}!" -f $Script:LogLevelSetting | Write-LogOutput -LogType LOG
            })

        #endregion
        $Script:LogWindowForm.Definition.Show()
        if (Invoke-LogWindowScrollToEnd) {
            $Script:TextBoxLog.ScrollToEnd()
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
