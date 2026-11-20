# ChoiceForm LeftButton event

$Script:ChoiceForm.Elements.LeftButton.Add_Click({
        param (
            $ButtonSender,
            $ButtonEventArgs
        )
        try {
            $_ | Show-EventInfo

            $Script:DialogResult = $Script:ChoiceForm.LeftButtonReturnValue
            # Read for a -ShowInput dialog; the collapsed box of any other dialog just holds "".
            $Script:ChoiceFormInputText = $Script:ChoiceForm.Elements.InputTextBox.Text
            $Script:ChoiceForm.Definition.Close()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
