$Script:ChoiceForm.Definition.Add_Loaded({
        try {
            $_ | Show-EventInfo
            $Script:ChoiceForm.Elements.LeftButton.Focus() | Out-Null
            $Script:ChoiceForm.Definition.Focus() | Out-Null
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
