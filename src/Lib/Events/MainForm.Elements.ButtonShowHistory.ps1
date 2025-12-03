$Script:MainForm.Elements.ButtonShowHistory.Add_Click({
        try {
            $_ | Show-EventInfo
            "Show history form" | Write-LogOutput -LogType DEBUG
            Open-SqlHistoryForm
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
