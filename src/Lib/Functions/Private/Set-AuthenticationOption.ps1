function Set-AuthenticationOption {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if ($null -ne $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {

            switch ($Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content) {
                { $_ -in @("Basic", "Windows", "OAuth" ) } {

                    if ($_ -eq "OAuth") {
                        $Script:MainForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Client ID:"
                        $Script:MainForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Client Secret:"
                    }
                    else {
                        $Script:MainForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Username:"
                        $Script:MainForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Password:"
                    }
                    $Script:MainForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBlockAppIdUri.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBlockEntraIdTenantId.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainForm.Elements.CheckBoxSavePassword.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxAppIdUri.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxEntraIdTenantId.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainForm.Elements.CheckBoxSavePassword.IsEnabled = $true
                    $Script:MainForm.Elements.TextBoxAppIdUri.IsEnabled = $true
                    $Script:MainForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $true
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
                    $Script:MainForm.Elements.TextBoxAppIdUri.IsEnabled = $false
                    $Script:MainForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $false
                    $Script:MainForm.Elements.TextBlockUserName | Set-TextBlockContent -Content "Username:"
                    $Script:MainForm.Elements.TextBlockPassword | Set-TextBlockContent -Content "Password:"
                    $Script:MainForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainForm.Elements.CheckBoxSavePassword.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainForm.Elements.TextBlockAppIdUri.Visibility = "Hidden"
                    $Script:MainForm.Elements.TextBlockEntraIdTenantId.Visibility = "Hidden"
                    $Script:MainForm.Elements.TextBlockUserName.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBlockPassword.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxUserName.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxPassword.Visibility = "Visible"
                    $Script:MainForm.Elements.TextBoxAppIdUri.Visibility = "Hidden"
                    $Script:MainForm.Elements.TextBoxEntraIdTenantId.Visibility = "Hidden"
                    $Script:MainForm.Elements.TextBoxUserName.IsEnabled = $true
                    $Script:MainForm.Elements.TextBoxPassword.IsEnabled = $true
                    $Script:MainForm.Elements.CheckBoxSavePassword.IsEnabled = $true
                    $Script:MainForm.Elements.TextBoxAppIdUri.Text = $null
                    $Script:MainForm.Elements.TextBoxEntraIdTenantId.Text = $null
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
            $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content | Set-ConfigProperty -Property "LastAuthentication"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
