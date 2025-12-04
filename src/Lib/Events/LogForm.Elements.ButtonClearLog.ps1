$Script:LogForm.Elements.ButtonClearLog.Add_Click({
        $_ | Show-EventInfo
        "Clear TextBoxLog" | Write-LogOutput -LogType DEBUG
        $Script:TextBoxLog.Clear()
        "Log cleared" | Write-LogOutput
    })

#$Script:LogForm.Elements.ButtonClearLogText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonClearLog"
#    })

#$Script:LogForm.Elements.ButtonClearLogImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonClearLog"
#    })
