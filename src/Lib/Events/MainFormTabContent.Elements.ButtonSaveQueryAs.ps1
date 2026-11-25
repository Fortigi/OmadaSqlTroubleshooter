$Script:MainForm.Elements.ButtonSaveQueryAs.Add_Click({
        try {
            $_ | Show-EventInfo

            if (!(Test-ConnectionRequirements)) {
                "Omada Url not set, cannot save the query!" | Write-LogOutput -LogType WARNING
                return
            }

            # Saves the editor as another, new query (a name is asked for); the tab then holds it.
            Save-SqlQueryAs
            Restore-MainFormFocus
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
