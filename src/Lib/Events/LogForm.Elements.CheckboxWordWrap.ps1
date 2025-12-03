$Script:LogForm.Elements.CheckboxWordWrap.Add_Checked({
        $_ | Show-EventInfo
        $Script:TextBoxLog.TextWrapping = "WrapWithOverflow"
        "Word wrap is enabled" | Write-LogOutput -LogType LOG
        $true | Set-ConfigProperty -Property "LogWindowWordWrap"
    })

$Script:LogForm.Elements.CheckboxWordWrap.Add_UnChecked({
        $_ | Show-EventInfo
        $Script:TextBoxLog.TextWrapping = "NoWrap"
        "Word wrap is disabled" | Write-LogOutput -LogType LOG
        $false | Set-ConfigProperty -Property "LogWindowWordWrap"

    })
