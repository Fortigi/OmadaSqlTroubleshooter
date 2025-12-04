$Script:MainForm.Elements.ButtonReset.Add_Click({
        try {
            $_ | Show-EventInfo
            "Reset" | Write-LogOutput -LogType LOG
            Reset-Application -ResetEditor
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#    $Script:MainForm.Elements.ButtonResetText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonReset"
#    }))

#$Script:MainForm.Elements.ButtonResetImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonReset"
#    }))
