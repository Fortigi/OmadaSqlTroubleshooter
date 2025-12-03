function Set-AuthenticationOption {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {

            switch ($Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {
                { $_ -in @("Basic", "Windows", "OAuth" ) } {

                    if ($_ -eq "OAuth") {
                        $Script:MainFormForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Client ID:"
                        $Script:MainFormForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Client Secret:"
                    }
                    else {
                        $Script:MainFormForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Username:"
                        $Script:MainFormForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Password:"
                    }
                    $Script:MainFormForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBlockAppIdUri.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBlockEntraIdTenantId.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.CheckBoxSavePassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxAppIdUri.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainFormForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainFormForm.Elements.CheckBoxSavePassword.IsEnabled = $true
                    $Script:MainFormForm.Elements.TextBoxAppIdUri.IsEnabled = $true
                    $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $true
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
                    $Script:MainFormForm.Elements.TextBoxAppIdUri.IsEnabled = $false
                    $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $false
                    $Script:MainFormForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Username:"
                    $Script:MainFormForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Password:"
                    $Script:MainFormForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.CheckBoxSavePassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainFormForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainFormForm.Elements.TextBlockAppIdUri.Visibility = "Hidden"
                    $Script:MainFormForm.Elements.TextBlockEntraIdTenantId.Visibility = "Hidden"
                    $Script:MainFormForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainFormForm.Elements.TextBoxAppIdUri.Visibility = "Hidden"
                    $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Visibility = "Hidden"
                    $Script:MainFormForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainFormForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainFormForm.Elements.CheckBoxSavePassword.IsEnabled = $true
                    $Script:MainFormForm.Elements.TextBoxAppIdUri.Text = $null
                    $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Text = $null
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
            $Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content | Set-ConfigProperty -Property "LastAuthentication"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
