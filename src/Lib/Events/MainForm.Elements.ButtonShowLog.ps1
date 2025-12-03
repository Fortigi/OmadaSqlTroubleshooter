$Script:MainForm.Elements.ButtonShowLog.Add_Click({
        try {
            $_ | Show-EventInfo
            if (Test-LogFormIsVisible) {
                "_Hide" | Write-LogOutput -LogType DEBUG
                $Script:LogForm.Definition.Close()
            }
            else {
                "Show log" | Write-LogOutput -LogType DEBUG
                Open-LogForm
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }

    })

#    $Script:MainForm.Elements.ButtonShowLogText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonShowLog"
#    }))))

#$Script:MainForm.Elements.ButtonShowLogImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonShowLog"
#    }))))
