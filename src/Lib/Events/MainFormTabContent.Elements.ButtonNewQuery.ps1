$Script:MainForm.Elements.ButtonNewQuery.Add_Click({
        try {
            $_ | Show-EventInfo

            # New clears the editor for a new, ad-hoc query, after offering to save unsaved work.
            # It creates nothing on the tenant - that happens on the first Save / Save as, which ask
            # for the name - and it never disables a button, so a failed save elsewhere can no
            # longer leave New greyed out (see Clear-TabQuery).
            Clear-TabQuery
            Restore-MainFormFocus
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
