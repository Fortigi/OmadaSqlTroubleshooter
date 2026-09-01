$Script:LogForm.Elements.CheckboxShowRequestBody.Add_Checked({
        $_ | Show-EventInfo
        Set-BodyRedactionState -Enabled $true
        $true | Set-ConfigProperty -Property "SkipBodyRedaction"
    })

$Script:LogForm.Elements.CheckboxShowRequestBody.Add_UnChecked({
        $_ | Show-EventInfo
        Set-BodyRedactionState -Enabled $false
        $false | Set-ConfigProperty -Property "SkipBodyRedaction"

    })
