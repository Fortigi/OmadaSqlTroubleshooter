$Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.Add_GotFocus({
        try {
            $_ | Show-EventInfo
            if ($null -eq $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
                $Script:RunTimeConfig.AuthenticationSet = $false
            }
            else {
                $Script:RunTimeConfig.AuthenticationSet = $true
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.Add_SelectionChanged({
        try {
            $_ | Show-EventInfo

            Set-AuthenticationOption
            "Changed authentication option to: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG

            if ($null -eq $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
                $Script:RunTimeConfig.AuthenticationSet = $false
            }
            else {
                $Script:RunTimeConfig.AuthenticationSet = $true
            }

            if ($Script:RunTimeConfig.AuthenticationSet -and ![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxURL.Text)) {
                Set-OmadaUrl
            }
            Test-ConnectionButton
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.Add_LostFocus({
        try {
            $_ | Show-EventInfo

            if ($null -eq $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {

                Set-AuthenticationOption
                "Changed authentication option to: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG

                if ($Script:RunTimeConfig.AuthenticationSet -and ![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxURL.Text)) {
                    Set-OmadaUrl
                }
                Test-ConnectionButton
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }

    })
