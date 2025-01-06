$Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.Add_GotFocus({
        $_ | Show-EventInfo
        if ($null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            $Script:RunTimeConfig.AuthenticationSet = $false
        }
        else {
            $Script:RunTimeConfig.AuthenticationSet = $true
        }
    })

$Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.Add_SelectionChanged({
        $_ | Show-EventInfo

        Set-AuthenticationOption
        "Changed authentication option to: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG

        if ($Script:RunTimeConfig.AuthenticationSet -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text)) {
            Set-OmadaUrl
        }
        Test-ConnectionSettings

    })

$Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.Add_LostFocus({
        $_ | Show-EventInfo

        if ($null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {

            Set-AuthenticationOption
            "Changed authentication option to: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG

            if ($Script:RunTimeConfig.AuthenticationSet -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text)) {
                Set-OmadaUrl
            }
            Test-ConnectionSettings
        }

    })
