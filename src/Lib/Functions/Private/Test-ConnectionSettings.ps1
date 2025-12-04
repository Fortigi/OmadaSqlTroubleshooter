function Test-ConnectionSettings {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ($Script:RunTimeConfig.ReconnectStatus -le 1 -or [string]::IsNullOrEmpty($Script:MainForm.Elements.TextBoxURL.Text) -or $null -eq $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            Set-SqlConnectionState -Status $false
        }
        else {
            if ($Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth" -and
                ([string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text) -or [string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password))) {
                Set-SqlConnectionState -Status $false
            }
            else {
                Set-SqlConnectionState -Status $true
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
