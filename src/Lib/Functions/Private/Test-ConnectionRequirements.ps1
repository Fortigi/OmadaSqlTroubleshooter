function Test-ConnectionRequirements {

    try {

        if ([string]::IsNullOrEmpty($Script:MainWindowForm.Elements.TextBoxURL.Text)) {
            "URL is empty" | Write-LogOutput -LogType DEBUG
            return $false
        }
        if ($null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            "Authentication option is not selected" | Write-LogOutput -LogType DEBUG
            return $false
        }
        if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth") {
            "OAuth is selected" | Write-LogOutput -LogType DEBUG
            if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text)) {
                "Username is empty" | Write-LogOutput -LogType DEBUG
                return $false
            }
            if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password)) {
                "Password is empty" | Write-LogOutput -LogType DEBUG
                return $false
            }
            "OAuth connection requirements are met" | Write-LogOutput -LogType DEBUG
            return $true
        }
        "Browser connection requirements are met" | Write-LogOutput -LogType DEBUG
        return $true
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
