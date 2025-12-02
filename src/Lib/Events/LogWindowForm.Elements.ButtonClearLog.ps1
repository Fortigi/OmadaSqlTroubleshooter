$Script:LogWindowForm.Elements.ButtonClearLog.Add_Click({
        $_ | Show-EventInfo
        "Clear TextBoxLog" | Write-LogOutput -LogType DEBUG
        $Script:TextBoxLog.Clear()
        "Log cleared" | Write-LogOutput
    })
