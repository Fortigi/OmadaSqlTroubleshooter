$Script:MainForm.Elements.ButtonRenameQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            Rename-SqlQuery
            Restore-MainFormFocus
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
