$Script:ChoiceForm.Definition.Add_Loaded({
        try {
            $_ | Show-EventInfo
            # Bring the dialog to the foreground and give it keyboard focus. At startup it can open
            # behind the main window / without focus, so Enter (the IsDefault LeftButton) would do
            # nothing until the user clicked the dialog first.
            $Script:ChoiceForm.Definition.Activate() | Out-Null
            $Script:ChoiceForm.Elements.LeftButton.Focus() | Out-Null
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
