function Test-ConnectionRequirements {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ([string]::IsNullOrEmpty($Script:MainFormForm.Elements.TextBoxURL.Text)) {
            "URL is empty" | Write-LogOutput -LogType DEBUG
            return $false
        }
        if ($null -eq $Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            "Authentication option is not selected" | Write-LogOutput -LogType DEBUG
            return $false
        }
        if ($Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth") {
            "OAuth is selected" | Write-LogOutput -LogType DEBUG
            if ([string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxUserName.Text)) {
                "Username is empty" | Write-LogOutput -LogType DEBUG
                return $false
            }
            if ([string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxPassword.Password)) {
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
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
