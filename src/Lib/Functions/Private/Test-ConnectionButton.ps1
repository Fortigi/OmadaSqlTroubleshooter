function Test-ConnectionButton {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if ([string]::IsNullOrEmpty($Script:MainWindowForm.Elements.TextBoxURL.Text) -or $null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            $Script:MainWindowForm.Elements.ButtonConnect.IsEnabled = $False
            Set-ButtonContent -ButtonObject $Script:MainWindowForm.Elements.ButtonConnect -Content "_Connect"
        }
        else {
            if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth" -and
            ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text) -or [string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password))) {
                $Script:MainWindowForm.Elements.ButtonConnect.IsEnabled = $False
                Set-ButtonContent -ButtonObject $Script:MainWindowForm.Elements.ButtonConnect -Content "_Connect"
            }
            else {
                $Script:MainWindowForm.Elements.ButtonConnect.IsEnabled = $true
                if ($Script:ConnectionStatus) {
                    Set-ButtonContent -ButtonObject $Script:MainWindowForm.Elements.ButtonConnect -Content "_Disconnect"
                }
                else {
                    Set-ButtonContent -ButtonObject $Script:MainWindowForm.Elements.ButtonConnect -Content "_Connect"
                }
            }
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
