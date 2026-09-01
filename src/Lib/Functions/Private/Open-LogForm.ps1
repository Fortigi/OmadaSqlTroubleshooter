function Open-LogForm {
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        "Opening Log form" | Write-LogOutput -LogType DEBUG
        $Script:LogForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\LogForm.xaml") -ParentForm $Script:MainForm.Definition
        Import-EventObjects -ClassName "LogForm"
        [Int]$Script:LogForm.PositionManager.PositionOffSetLeft = 1200

        $true | Set-ConfigProperty -Property "LogFormOpen"

        $Script:LogForm.Definition.ShowInTaskbar = $false
        $Script:TextBoxLog = $Script:LogForm.Definition.FindName("TextBoxLog")
        if ($Script:AppGlobalConfig.LogFormWordWrap) {
            $Script:TextBoxLog.TextWrapping = "WrapWithOverflow"
            $Script:LogForm.Elements.CheckboxWordWrap.IsChecked = $true
            "Word wrap is enabled" | Write-LogOutput -LogType LOG
            $true | Set-ConfigProperty -Property "LogFormWordWrap"
        }
        else {
            $Script:TextBoxLog.TextWrapping = "NoWrap"
            $Script:LogForm.Elements.CheckboxWordWrap.IsChecked = $false
            $false | Set-ConfigProperty -Property "LogFormWordWrap"
        }
        if ($Script:RunTimeConfig.Logging.LogToConsole) {
            $Script:LogForm.Elements.CheckboxConsoleLog.IsChecked = $true
            "Console logging is enabled" | Write-LogOutput -LogType LOG
            $true | Set-ConfigProperty -Property "CheckboxConsoleLog"
        }
        else {
            $Script:LogForm.Elements.CheckboxConsoleLog.IsChecked = $false
            $false | Set-ConfigProperty -Property "CheckboxConsoleLog"
        }

        #Set log level to show
        if (![string]::IsNullOrWhiteSpace($Script:RunTimeConfig.Logging.LogLevel)) {
            "Set form log level to: {0}" -f $Script:RunTimeConfig.Logging.LogLevel | Write-LogOutput -LogType DEBUG
            if (($LogForm.Elements.ComboBoxSelectLogLevel.Items | Measure-Object).count -le 0 -and !$LogForm.Elements.ComboBoxSelectLogLevel.Items.Content.Contains($Script:RunTimeConfig.Logging.LogLevel)) {
                $ComboBoxSelectLogLevelItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectLogLevelItem.Content = $Script:RunTimeConfig.Logging.LogLevel
                $LogForm.Elements.ComboBoxSelectLogLevel.Items.Add($ComboBoxSelectLogLevelItem) | Out-Null
            }
            $LogForm.Elements.ComboBoxSelectLogLevel.SelectedValue = $LogForm.Elements.ComboBoxSelectLogLevel.Items | Where-Object { $_.Content -eq $Script:RunTimeConfig.Logging.LogLevel }
            $Script:RunTimeConfig.Logging.LogLevelSetting = $Script:RunTimeConfig.Logging.LogLevel
        }
        else {
            # The schema is the single source of truth for this default; it used to be a third,
            # separate literal here.
            $DefaultLogLevel = Get-ConfigSchemaDefault -Property "LogLevel"
            "Set form log level to the schema default because it was not set: {0}" -f $DefaultLogLevel | Write-LogOutput -LogType DEBUG
            if (($LogForm.Elements.ComboBoxSelectLogLevel.Items | Measure-Object).count -le 0 -and !$LogForm.Elements.ComboBoxSelectLogLevel.Items.Content.Contains($DefaultLogLevel)) {
                $ComboBoxSelectLogLevelItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxSelectLogLevelItem.Content = $DefaultLogLevel
                $LogForm.Elements.ComboBoxSelectLogLevel.Items.Add($ComboBoxSelectLogLevelItem) | Out-Null
            }
            $LogForm.Elements.ComboBoxSelectLogLevel.SelectedValue = $LogForm.Elements.ComboBoxSelectLogLevel.Items | Where-Object { $_.Content -eq $DefaultLogLevel }
            $Script:RunTimeConfig.Logging.LogLevelSetting = $LogForm.Elements.ComboBoxSelectLogLevel.SelectedValue.Content
        }

        if ($null -ne ($Script:LogForm.Definition | Get-FormPositionConfig)) {
            $Position = $Script:LogForm.Definition | Get-FormPositionConfig
            "Log form position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:LogForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
            $Script:LogForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
        }

        $Script:TextBoxLog.remove_TextChanged({
                $_ | Show-EventInfo
                "Clear AppLogObject" | Write-LogOutput -LogType DEBUG
                $Script:RunTimeConfig.Logging.AppLogObject.Clear()
            })


        $Script:LogForm.Definition.Show()
        if ($Script:TextBoxLog.IsLoaded -and (Invoke-LogFormScrollToEnd)) {
            $Script:TextBoxLog.ScrollToEnd()
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
