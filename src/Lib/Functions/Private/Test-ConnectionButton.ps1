function Test-ConnectionButton {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        if ([string]::IsNullOrEmpty($Script:MainWindowForm.Elements.TextBoxURL.Text) -or $null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            $Script:MainWindowForm.Elements.ButtonConnect.IsEnabled = $false
             $Script:MainWindowForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
        }
        else {
            if ($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth" -and
                (
                    [string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxUserName.Text) -or
                    [string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxPassword.Password) -or
                    [string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.Text)
                )
            ) {
                $Script:MainWindowForm.Elements.ButtonConnect.IsEnabled = $false
                 $Script:MainWindowForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
            }
            else {
                $Script:MainWindowForm.Elements.ButtonConnect.IsEnabled = $true
                if ($Script:ConnectionStatus) {
                     $Script:MainWindowForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Disconnect"
                }
                else {
                     $Script:MainWindowForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
                }
            }
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
