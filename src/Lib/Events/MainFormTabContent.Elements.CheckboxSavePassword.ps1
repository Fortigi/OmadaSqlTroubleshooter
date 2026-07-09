$Script:MainForm.Elements.CheckboxSavePassword.Add_Checked({
        try {
            $_ | Show-EventInfo

            $true | Set-ConfigProperty -Property "SavePassword"
            if ($null -ne $Script:MainForm.Elements.TextBoxPassword.Password) {
                $Script:MainForm.Elements.TextBoxPassword.Password | Set-ConfigProperty -Property "Password"
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.CheckboxSavePassword.Add_Unchecked({
        try {
            $_ | Show-EventInfo
            $false | Set-ConfigProperty -Property "SavePassword"
            $null | Set-ConfigProperty -Property "Password"
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
