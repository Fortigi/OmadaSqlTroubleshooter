$Script:MainFormForm.Elements.CheckboxSavePassword.Add_Checked({
        try {
            $_ | Show-EventInfo

            $true | Set-ConfigProperty -Property "SavePassword"
            $Script:RunTimeConfig.SavePassword = $true
            if ($null -ne $Script:MainFormForm.Elements.TextBoxPassword.Password) {
                $Script:MainFormForm.Elements.TextBoxPassword.Password | Set-ConfigProperty -Property "Password"
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainFormForm.Elements.CheckboxSavePassword.Add_Unchecked({
        try {
            $_ | Show-EventInfo
            $false | Set-ConfigProperty -Property "SavePassword"
            $Script:RunTimeConfig.SavePassword = $false
            $null | Set-ConfigProperty -Property "Password"
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
