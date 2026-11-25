$Script:MainForm.Elements.ButtonOpenQueryManager.Add_Click({
        try {
            $_ | Show-EventInfo

            # Every query on the tenant, with create, rename, delete, details and history.
            Open-QueryManagerForm
            Restore-MainFormFocus
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
