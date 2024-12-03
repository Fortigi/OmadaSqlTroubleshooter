function Set-AuthenticationOption {

    try {
        if ($Null -ne $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {

            switch ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {
                { $_ -in @("Basic", "Windows", "OAuth" ) } {

                    if ($_ -eq "OAuth") {
                        $Script:MainWindowForm.Elements.LabelUserName.Content = "Client ID:"
                        $Script:MainWindowForm.Elements.LabelPassword.Content = "Client Secret:"
                    }
                    else {
                        $Script:MainWindowForm.Elements.LabelUserName.Content = "Username:"
                        $Script:MainWindowForm.Elements.LabelPassword.Content = "Password:"
                    }
                    $Script:MainWindowForm.Elements.LabelUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.LabelPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $True
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $True
                    if (!$InvokeOmadaRestMethodParam.ContainsKey("Credential")) {
                        $InvokeOmadaRestMethodParam.Add("Credential", $Null)
                    }
                }

                default {
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $False
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $False
                    $Script:MainWindowForm.Elements.LabelUserName.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.LabelPassword.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxPassword.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Text = ""
                    $Script:MainWindowForm.Elements.TextBoxPassword.Password = ""
                    $Null | Invoke-ProcessConfigSettings -Property "UserName"
                    if ($InvokeOmadaRestMethodParam.ContainsKey("Credential")) {
                        $InvokeOmadaRestMethodParam.Remove("Credential")
                    }
                }
            }
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content | Invoke-ProcessConfigSettings -Property "LastAuthentication"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
