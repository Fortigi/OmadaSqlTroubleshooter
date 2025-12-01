function Set-AuthenticationOption {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {

            switch ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {
                { $_ -in @("Basic", "Windows", "OAuth" ) } {

                    if ($_ -eq "OAuth") {
                        $Script:MainWindowForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Client ID:"
                        $Script:MainWindowForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Client Secret:"
                    }
                    else {
                        $Script:MainWindowForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Username:"
                        $Script:MainWindowForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Password:"
                    }
                    $Script:MainWindowForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBlockAppIdUri.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBlockEntraIdTenantId.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.CheckBoxSavePassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxAppIdUri.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainWindowForm.Elements.CheckBoxSavePassword.IsEnabled = $true
                    $Script:MainWindowForm.Elements.TextBoxAppIdUri.IsEnabled = $true
                    $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $true
                    if (!$Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                        $Script:RunTimeData.RestMethodParam.Add("Credential", $null)
                    }
                    if (!$Script:RunTimeData.RestMethodParam.ContainsKey("EntraApplicationIdUri")) {
                        $Script:RunTimeData.RestMethodParam.Add("EntraApplicationIdUri", $null)
                        $null | Set-ConfigProperty -Property "EntraApplicationIdUri"
                    }
                    if (!$Script:RunTimeData.RestMethodParam.ContainsKey("EntraIdTenantId")) {
                        $Script:RunTimeData.RestMethodParam.Add("EntraIdTenantId", $null)
                        $null | Set-ConfigProperty -Property "EntraIdTenantId"
                    }
                }

                default {
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $false
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $false
                    $Script:MainWindowForm.Elements.TextBoxAppIdUri.IsEnabled = $false
                    $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $false
                    $Script:MainWindowForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Username:"
                    $Script:MainWindowForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Password:"
                    $Script:MainWindowForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.CheckBoxSavePassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainWindowForm.Elements.TextBlockAppIdUri.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBlockEntraIdTenantId.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainWindowForm.Elements.TextBoxAppIdUri.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Visibility = "Hidden"
                    $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainWindowForm.Elements.CheckBoxSavePassword.IsEnabled = $true
                    $Script:MainWindowForm.Elements.TextBoxAppIdUri.Text = $null
                    $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Text = $null
                    if ($Script:RunTimeData.RestMethodParam.ContainsKey("EntraApplicationIdUri")) {
                        $Script:RunTimeData.RestMethodParam.Remove("EntraApplicationIdUri")
                        $null | Set-ConfigProperty -Property "EntraApplicationIdUri"

                    }
                    if ($Script:RunTimeData.RestMethodParam.ContainsKey("EntraIdTenantId")) {
                        $Script:RunTimeData.RestMethodParam.Remove("EntraIdTenantId")
                        $null | Set-ConfigProperty -Property "EntraIdTenantId"
                    }
                }
            }
            $Script:RunTimeConfig.AuthenticationSet = $true
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content | Set-ConfigProperty -Property "LastAuthentication"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
