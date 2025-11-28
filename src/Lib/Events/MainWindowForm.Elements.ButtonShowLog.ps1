$Script:MainWindowForm.Elements.ButtonShowLog.Add_Click({
        try {
            $_ | Show-EventInfo
            if (Test-LogWindowOpen) {
                "_Hide" | Write-LogOutput -LogType DEBUG
                $Script:LogWindowForm.Definition.Close()
            }
            else {
                "Show log" | Write-LogOutput -LogType DEBUG
                Open-LogWindow
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }

    })
