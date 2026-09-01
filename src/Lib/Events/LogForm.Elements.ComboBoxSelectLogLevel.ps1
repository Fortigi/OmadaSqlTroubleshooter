$Script:LogForm.Elements.ComboBoxSelectLogLevel.Add_SelectionChanged({
        $_ | Show-EventInfo
        # The combo box starts with no selection, so Open-LogForm can apply the stored level after
        # this handler is wired without a preselected item storing a level nobody chose.
        if ($null -eq $Script:LogForm.Elements.ComboBoxSelectLogLevel.SelectedItem) {
            return
        }

        $Script:LogForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content | Set-ConfigProperty -Property "LogLevel"
        $Script:RunTimeConfig.Logging.LogLevelSetting = $Script:LogForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content
        # Keep the value Open-LogForm reads in step, so reopening the log viewer in the same session
        # shows the level that is actually in effect.
        $Script:RunTimeConfig.Logging.LogLevel = $Script:LogForm.Elements.ComboBoxSelectLogLevel.SelectedItem.Content
        "Logging set to {0}!" -f $Script:RunTimeConfig.Logging.LogLevelSetting | Write-LogOutput -LogType LOG
    })
