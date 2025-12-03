$Script:MainFormForm.Elements.ButtonShowHistory.Add_Click({
        try {
            $_ | Show-EventInfo
            "Show history window" | Write-LogOutput -LogType DEBUG
            Open-SqlHistoryForm
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
