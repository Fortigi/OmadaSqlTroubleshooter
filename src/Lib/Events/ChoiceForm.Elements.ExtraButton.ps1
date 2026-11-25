# ChoiceForm ExtraButton event (the optional third button, see Open-ChoiceForm -ExtraButtonText)

$Script:ChoiceForm.Elements.ExtraButton.Add_Click({
        param (
            $ButtonSender,
            $ButtonEventArgs
        )
        try {
            $_ | Show-EventInfo

            $Script:DialogResult = $Script:ChoiceForm.ExtraButtonReturnValue
            $Script:ChoiceForm.Definition.Close()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
