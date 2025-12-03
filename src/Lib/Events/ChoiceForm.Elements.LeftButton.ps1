# ChoiceForm LeftButton event

$Script:ChoiceForm.Elements.LeftButton.Add_Click({
        param (
            $ButtonSender,
            $ButtonEventArgs
        )
        try {
            $_ | Show-EventInfo

            $Script:DialogResult = $Script:ChoiceForm.LeftButtonReturnValue
            $Script:ChoiceForm.Definition.Close()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
