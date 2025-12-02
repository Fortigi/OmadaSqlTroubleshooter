$Script:MainWindowForm.Elements.ButtonShowHistory.Add_Click({
        try {
            $_ | Show-EventInfo
            "Show history window" | Write-LogOutput -LogType DEBUG
            Open-SqlHistoryWindow
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
