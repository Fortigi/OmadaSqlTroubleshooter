$Script:MainWindowForm.Elements.ButtonReset.Add_Click({
        $_ | Show-EventInfo
        "Reset" | Write-LogOutput -LogType LOG
        Reset-Application -ResetEditor
    })
