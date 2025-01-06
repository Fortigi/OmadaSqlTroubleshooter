function Set-AuthenticationOption {

    try {
        if ($Null -ne $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {

            switch ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {
                { $_ -in @("Basic", "Windows", "OAuth" ) } {

                    if ($_ -eq "OAuth") {
                        $Script:MainWindowForm.Elements.LabelUserName | Set-LabelContent-Content "Client ID:"
                        $Script:MainWindowForm.Elements.LabelPassword | Set-LabelContent-Content "Client Secret:"
                    }
                    else {
                        $Script:MainWindowForm.Elements.LabelUserName | Set-LabelContent-Content "Username:"
                        $Script:MainWindowForm.Elements.LabelPassword | Set-LabelContent-Content "Password:"
                    }
                    $Script:MainWindowForm.Elements.LabelUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.LabelPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $True
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $True
                    if (!$Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                        $Script:RunTimeData.RestMethodParam.Add("Credential", $Null)
                    }
                }

                default {
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $False
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $False
                    $Script:MainWindowForm.Elements.LabelUserName.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.LabelPassword.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxPassword.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxUserName | Set-TextBlockText -Text $null
                    $Script:MainWindowForm.Elements.TextBoxPassword.Password = ""
                    $Null | Invoke-ConfigSetting -Property "UserName"
                    if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                        $Script:RunTimeData.RestMethodParam.Remove("Credential")
                    }
                }
            }
            $Script:RunTimeConfig.AuthenticationSet = $True
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content | Invoke-ConfigSetting -Property "LastAuthentication"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
