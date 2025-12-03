$Script:LogForm.Elements.ComboBoxSelectLogLevel.Add_SelectionChanged({
        $_ | Show-EventInfo
        $Script:LogForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content | Set-ConfigProperty -Property "LogLevel"
        $Script:RunTimeConfig.Logging.LogLevelSetting = $Script:LogForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content
        "Logging set to {0}!" -f $Script:RunTimeConfig.Logging.LogLevelSetting | Write-LogOutput -LogType LOG
    })
