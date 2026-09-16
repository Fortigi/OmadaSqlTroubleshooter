$Script:LogForm.Elements.CheckboxSessionLogFile.Add_Checked({
        $_ | Show-EventInfo
        Set-SessionLogFileEnabled -Enabled $true | Out-Null
        Update-LogFormSessionLogPath
    })

$Script:LogForm.Elements.CheckboxSessionLogFile.Add_UnChecked({
        $_ | Show-EventInfo
        Set-SessionLogFileEnabled -Enabled $false | Out-Null
        Update-LogFormSessionLogPath
    })
