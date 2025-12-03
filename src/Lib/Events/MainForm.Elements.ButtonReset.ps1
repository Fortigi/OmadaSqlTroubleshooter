$Script:MainFormForm.Elements.ButtonReset.Add_Click({
        try {
            $_ | Show-EventInfo
            "Reset" | Write-LogOutput -LogType LOG
            Reset-Application -ResetEditor
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
