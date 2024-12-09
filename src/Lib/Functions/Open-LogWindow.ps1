function Open-LogWindow {
    try {
        #Log window creation
        "Opening Log window" | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm = New-FormObject -FormPath (Join-Path $ScriptRootFolder -ChildPath "lib\ui\LogWindow.xaml") -ParentForm $Script:MainWindowForm.Definition
        $true | Invoke-ConfigSetting -Property "LogWindowFormOpen"

        $Script:LogWindowForm.Definition.ShowInTaskbar = $false
        $Script:TextBoxLog = $Script:LogWindowForm.Definition.FindName("TextBoxLog")
        if ($Script:AppConfig.LogWindowWordWrap) {
            $Script:TextBoxLog.TextWrapping = "WrapWithOverflow"
            $Script:LogWindowForm.Elements.CheckboxWordWrap.IsChecked = $true
            "Word wrap is enabled" | Write-LogOutput -LogType LOG
            $true | Invoke-ConfigSetting -Property "LogWindowWordWrap"
        }
        else {
            $Script:TextBoxLog.TextWrapping = "NoWrap"
            $Script:LogWindowForm.Elements.CheckboxWordWrap.IsChecked = $false
            $false | Invoke-ConfigSetting -Property "LogWindowWordWrap"
        }
        if ($Script:LogToConsole) {
            $Script:LogWindowForm.Elements.CheckboxConsoleLog.IsChecked = $true
            "Console logging is enabled" | Write-LogOutput -LogType LOG
            $true | Invoke-ConfigSetting -Property "CheckboxConsoleLog"
        }
        else {
            $Script:LogWindowForm.Elements.CheckboxConsoleLog.IsChecked = $false
            $false | Invoke-ConfigSetting -Property "CheckboxConsoleLog"
        }

        #Set log level to show
        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.LogLevel)) {
            "Set window log level to: {0}" -f $Script:AppConfig.LogLevel | Write-LogOutput -LogType DEBUG
            if (($LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Measure-Object).count -le 0 -and !$LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Content.Contains($Script:AppConfig.LogLevel)) {
                $ComboBoxSelectLogLevelItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectLogLevelItem.Content = $Script:AppConfig.LogLevel
                $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Add($ComboBoxSelectLogLevelItem) | Out-Null
            }
            $LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedValue = $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Where-Object { $_.Content -eq $Script:AppConfig.LogLevel }
            $Script:LogLevelSetting = $Script:AppConfig.LogLevel
        }
        else {
            "Set window log level to default because it was not set: INFO" | Write-LogOutput -LogType DEBUG
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
                $_ | Show-EventInfo -LogType VERBOSE2
                if (!$Script:PositionManagerLogWindow.Synchronizing) {
                    $Script:PositionManagerLogWindow.Synchronizing = $true
                    "MainWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
                    "LogWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogWindowForm.Definition.Left, $Script:LogWindowForm.Definition.Top, $Script:LogWindowForm.Definition.Width , $Script:LogWindowForm.Definition.Height | Write-LogOutput -LogType VERBOSE2
                    $Script:LogWindowForm.Definition.Dispatcher.Invoke({
                            $_ | Show-EventInfo -LogType VERBOSE2
                            $Script:PositionManagerLogWindow.PositionOffSetLeft = [Int]::Abs($Script:LogWindowForm.Definition.Left) - [Int]::Abs($Script:MainWindowForm.Definition.Left)
                            "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:PositionManagerLogWindow.PositionOffSetLeft | Write-LogOutput -LogType VERBOSE2
                            $Script:PositionManagerLogWindow.PositionOffSetTop = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Top)
                            "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:PositionManagerLogWindow.PositionOffSetTop | Write-LogOutput -LogType VERBOSE2
                            $Script:PositionManagerLogWindow.Synchronizing = $false
                        }, [System.Windows.Threading.DispatcherPriority]::Render)
                }
            })

        $Script:LogWindowForm.Definition.Add_SizeChanged({
                $_ | Show-EventInfo -LogType VERBOSE2
                $Script:LogWindowForm.Size = $Script:LogWindowForm.Definition | Get-WindowSize
            })

        #endregion

        if ($null -ne ($Script:LogWindowForm.Definition | Get-WindowPositionConfig)) {
            $Position = $Script:LogWindowForm.Definition | Get-WindowPositionConfig
            "Log window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:LogWindowForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
            $Script:LogWindowForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
        }

        #region LogWindowForm events
        $Script:LogWindowForm.Definition.Add_Loaded({
                $_ | Show-EventInfo
                $Script:PositionManagerLogWindow.Synchronizing = $true
                $Script:LogWindowForm.Definition.Dispatcher.Invoke({
                        "MainWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
                        $Script:LogWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top)
                        "LogWindowForm Top: {0}" -f $Script:LogWindowForm.Definition.Top | Write-LogOutput -LogType DEBUG
                        $Script:LogWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:MainWindowForm.Definition.Width)
                        "LogWindowForm Left: {0}" -f $Script:LogWindowForm.Definition.Left | Write-LogOutput -LogType DEBUG
                        $Script:PositionManagerLogWindow.PositionOffSetLeft = [Int]::Abs($Script:LogWindowForm.Definition.Left) - [Int]::Abs($Script:MainWindowForm.Definition.Left)
                        "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:PositionManagerLogWindow.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                        $Script:PositionManagerLogWindow.PositionOffSetTop = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Top)
                        "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:PositionManagerLogWindow.PositionOffSetTop | Write-LogOutput -LogType DEBUG
                        if ($null -ne ($Script:LogWindowForm.Definition | Get-WindowSizeConfig)) {
                            $Size = $Script:LogWindowForm.Definition | Get-WindowSizeConfig
                            "Log window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                            $Script:LogWindowForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                            "LogWindowForm Width: {0}" -f $Script:LogWindowForm.Definition.Width | Write-LogOutput -LogType DEBUG
                            $Script:LogWindowForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
                            "LogWindowForm Height: {0}" -f $Script:LogWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
                        }
                        $Script:PositionManagerLogWindow.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)
                $Script:MainWindowForm.Elements.ButtonShowLog | Set-ButtonContent -Content "_Hide Log"
                $Script:TextBoxLog.Text = $AppLogObject
                $Script:PositionManagerLogWindow.PositionOffSetLeft = [Int]::Abs($Script:LogWindowForm.Definition.Left) - [Int]::Abs($Script:MainWindowForm.Definition.Left)
                "PositionManagerLogWindow PositionOffSetLeft: {0}" -f $Script:PositionManagerLogWindow.PositionOffSetLeft | Write-LogOutput -LogType DEBUG
                $Script:PositionManagerLogWindow.PositionOffSetTop = [Int]::Abs($Script:LogWindowForm.Definition.Top) - [Int]::Abs($Script:MainWindowForm.Definition.Top)
                "PositionManagerLogWindow PositionOffSetTop: {0}" -f $Script:PositionManagerLogWindow.PositionOffSetTop | Write-LogOutput -LogType DEBUG
                "LogWindowForm Position: {0}x{1}, Dimensions: {2}x{3}" -f $Script:LogWindowForm.Definition.Left, $Script:LogWindowForm.Definition.Top, $Script:LogWindowForm.Definition.Width , $Script:LogWindowForm.Definition.Height | Write-LogOutput -LogType DEBUG
                $Script:LogWindowForm.State = "Open"
            })

        $Script:LogWindowForm.Definition.Add_Closing({
                $_ | Show-EventInfo
                $Script:LogWindowForm.State = "Closing"
                Save-WindowMeasurements
                if ($Script:MainWindowForm.State -eq "Open") {
                    $false | Invoke-ConfigSetting -Property "LogWindowFormOpen"
                }
            })

        $Script:LogWindowForm.Definition.Add_Closed({
                $_ | Show-EventInfo
                $Script:LogWindowForm.State = "Closed"
                $Script:MainWindowForm.Elements.ButtonShowLog | Set-ButtonContent -Content "Log"
            })

        $Script:LogWindowForm.Elements.ButtonClearLog.Add_Click({
                $_ | Show-EventInfo
                "Clear TextBoxLog" | Write-LogOutput -LogType DEBUG
                $Script:TextBoxLog.Clear()
                "Log cleared" | Write-LogOutput
            })

        $Script:TextBoxLog.remove_TextChanged({
                $_ | Show-EventInfo
                "Clear AppLogObject" | Write-LogOutput -LogType DEBUG
                $AppLogObject.Clear()
            })

        $Script:LogWindowForm.Elements.ButtonExportLogFile.Add_Click({
                $_ | Show-EventInfo
                $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
                $SaveFileDialog.Filter = "Log files (*.log) | *.log | All files (*.*) | *.*"
                "Dialog Filter: {0}" -f $SaveFileDialog.Filter | Write-LogOutput -LogType DEBUG
                $SaveFileDialog.Title = "Save Log File"
                "Dialog Title: {0}" -f $SaveFileDialog.Title | Write-LogOutput -LogType DEBUG
                $SaveFileDialog.FileName = "OmadaTroubleshooter.log"
                "Dialog Initial FileName: {0}" -f $SaveFileDialog.FileName | Write-LogOutput -LogType DEBUG
                if ($SaveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    if ($Null -eq $SaveFileDialog.FileName) {
                        return
                    }
                    else {
                        $AppLogObject | Set-Content $SaveFileDialog.FileName -Encoding UTF8
                        "File saved to: {0}" -f $SaveFileDialog.FileName | Write-LogOutput -LogType DEBUG

                    }
                }
                else {
                    "File was not saved!" | Write-LogOutput -LogType DEBUG
                }
            })

        $Script:LogWindowForm.Elements.ComboBoxSelectLogLevel.Add_SelectionChanged({
                $_ | Show-EventInfo
                $Script:LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content | Invoke-ConfigSetting -Property "LogLevel"
                $Script:LogLevelSetting = $Script:LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content
                "Logging set to {0}!" -f $Script:LogLevelSetting | Write-LogOutput -LogType LOG
            })


        $Script:LogWindowForm.Elements.CheckboxWordWrap.Add_Checked({
                $_ | Show-EventInfo
                $Script:TextBoxLog.TextWrapping = "WrapWithOverflow"
                "Word wrap is enabled" | Write-LogOutput -LogType LOG
                $true | Invoke-ConfigSetting -Property "LogWindowWordWrap"
            })

        $Script:LogWindowForm.Elements.CheckboxWordWrap.Add_UnChecked({
                $_ | Show-EventInfo
                $Script:TextBoxLog.TextWrapping = "NoWrap"
                "Word wrap is disabled" | Write-LogOutput -LogType LOG
                $false | Invoke-ConfigSetting -Property "LogWindowWordWrap"

            })

        $Script:LogWindowForm.Elements.CheckboxConsoleLog.Add_Checked({
                $_ | Show-EventInfo
                $Script:LogToConsole = $true
                "Console logging is enabled" | Write-LogOutput -LogType LOG
                $true | Invoke-ConfigSetting -Property "CheckboxConsoleLog"
            })

        $Script:LogWindowForm.Elements.CheckboxConsoleLog.Add_UnChecked({
                $_ | Show-EventInfo
                $Script:LogToConsole = $false
                "Console logging is disabled" | Write-LogOutput -LogType LOG
                $false | Invoke-ConfigSetting -Property "CheckboxConsoleLog"

            })

        #endregion
        $Script:LogWindowForm.Definition.Show()
        if ($Script:TextBoxLog.IsLoaded -and (Invoke-LogWindowScrollToEnd)) {
            $Script:TextBoxLog.ScrollToEnd()
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
