function Open-LogWindow {
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        #Log window creation
        "Opening Log window" | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\LogWindow.xaml") -ParentForm $Script:MainWindowForm.Definition

        [Int]$Script:LogWindowForm.PositionManager.PositionOffSetLeft = 1200

        $true | Set-ConfigProperty -Property "LogWindowFormOpen"

        $Script:LogWindowForm.Definition.ShowInTaskbar = $false
        $Script:TextBoxLog = $Script:LogWindowForm.Definition.FindName("TextBoxLog")
        if ($Script:AppConfig.LogWindowWordWrap) {
            $Script:TextBoxLog.TextWrapping = "WrapWithOverflow"
            $Script:LogWindowForm.Elements.CheckboxWordWrap.IsChecked = $true
            "Word wrap is enabled" | Write-LogOutput -LogType LOG
            $true | Set-ConfigProperty -Property "LogWindowWordWrap"
        }
        else {
            $Script:TextBoxLog.TextWrapping = "NoWrap"
            $Script:LogWindowForm.Elements.CheckboxWordWrap.IsChecked = $false
            $false | Set-ConfigProperty -Property "LogWindowWordWrap"
        }
        if ($Script:RunTimeConfig.Logging.LogToConsole) {
            $Script:LogWindowForm.Elements.CheckboxConsoleLog.IsChecked = $true
            "Console logging is enabled" | Write-LogOutput -LogType LOG
            $true | Set-ConfigProperty -Property "CheckboxConsoleLog"
        }
        else {
            $Script:LogWindowForm.Elements.CheckboxConsoleLog.IsChecked = $false
            $false | Set-ConfigProperty -Property "CheckboxConsoleLog"
        }

        #Set log level to show
        if (![string]::IsNullOrWhiteSpace($Script:RunTimeConfig.Logging.LogLevel)) {
            "Set window log level to: {0}" -f $Script:RunTimeConfig.Logging.LogLevel | Write-LogOutput -LogType DEBUG
            if (($LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Measure-Object).count -le 0 -and !$LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Content.Contains($Script:RunTimeConfig.Logging.LogLevel)) {
                $ComboBoxSelectLogLevelItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectLogLevelItem.Content = $Script:RunTimeConfig.Logging.LogLevel
                $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Add($ComboBoxSelectLogLevelItem) | Out-Null
            }
            $LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedValue = $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Where-Object { $_.Content -eq $Script:RunTimeConfig.Logging.LogLevel }
            $Script:RunTimeConfig.Logging.LogLevelSetting = $Script:RunTimeConfig.Logging.LogLevel
        }
        else {
            "Set window log level to default because it was not set: INFO" | Write-LogOutput -LogType DEBUG
            if (($LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Measure-Object).count -le 0 -and !$LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Content.Contains("INFO")) {
                $ComboBoxSelectLogLevelItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectLogLevelItem.Content = "INFO"
                $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items.Add($ComboBoxSelectLogLevelItem) | Out-Null
            }
            $LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedValue = $LogWindowForm.Elements.ComboBoxSelectLogLevel.Items | Where-Object { $_.Content -eq "INFO" }
            $Script:RunTimeConfig.Logging.LogLevelSetting = $LogWindowForm.Elements.ComboBoxSelectLogLevel.SelectedValue.Content
        }

        if ($null -ne ($Script:LogWindowForm.Definition | Get-WindowPositionConfig)) {
            $Position = $Script:LogWindowForm.Definition | Get-WindowPositionConfig
            "Log window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:LogWindowForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
            $Script:LogWindowForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
        }

        $Script:TextBoxLog.remove_TextChanged({
                $_ | Show-EventInfo
                "Clear AppLogObject" | Write-LogOutput -LogType DEBUG
                $Script:RunTimeConfig.Logging.AppLogObject.Clear()
            })


        $Script:LogWindowForm.Definition.Show()
        if ($Script:TextBoxLog.IsLoaded -and (Invoke-LogWindowScrollToEnd)) {
            $Script:TextBoxLog.ScrollToEnd()
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
