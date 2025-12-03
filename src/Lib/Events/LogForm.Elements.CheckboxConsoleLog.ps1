$Script:LogForm.Elements.CheckboxConsoleLog.Add_Checked({
        $_ | Show-EventInfo
        $Script:RunTimeConfig.Logging.LogToConsole = $true
        "Console logging is enabled" | Write-LogOutput -LogType LOG
        $true | Set-ConfigProperty -Property "CheckboxConsoleLog"
    })

$Script:LogForm.Elements.CheckboxConsoleLog.Add_UnChecked({
        $_ | Show-EventInfo
        $Script:RunTimeConfig.Logging.LogToConsole = $false
        "Console logging is disabled" | Write-LogOutput -LogType LOG
        $false | Set-ConfigProperty -Property "CheckboxConsoleLog"

    })
