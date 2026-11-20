$Script:MainForm.Elements.ButtonDeleteQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            Remove-SavedSqlQuery
            Restore-MainFormFocus
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
