# ChoiceForm RightButton event

$Script:ChoiceForm.Elements.RightButton.Add_Click({
        param (
            $ButtonSender,
            $ButtonEventArgs
        )
        try {
            $_ | Show-EventInfo

            $Script:DialogResult = $Script:ChoiceForm.RightButtonReturnValue
            $Script:ChoiceForm.Definition.Close()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
