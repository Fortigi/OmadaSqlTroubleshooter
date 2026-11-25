$Script:ChoiceForm.Definition.Add_Loaded({
        try {
            $_ | Show-EventInfo
            # Bring the dialog to the foreground and give it keyboard focus. At startup it can open
            # behind the main window / without focus, so Enter (the IsDefault LeftButton) would do
            # nothing until the user clicked the dialog first.
            $Script:ChoiceForm.Definition.Activate() | Out-Null
            # A dialog asking for text puts the caret in the box, with the suggestion selected so typing
            # replaces it. Enter still submits: the LeftButton is IsDefault.
            if ($Script:ChoiceForm.Elements.InputTextBox.Visibility -eq [System.Windows.Visibility]::Visible) {
                $Script:ChoiceForm.Elements.InputTextBox.Focus() | Out-Null
                $Script:ChoiceForm.Elements.InputTextBox.SelectAll()
            }
            else {
                $Script:ChoiceForm.Elements.LeftButton.Focus() | Out-Null
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
