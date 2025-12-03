function Test-ConnectionButton {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ([string]::IsNullOrEmpty($Script:MainFormForm.Elements.TextBoxURL.Text) -or $null -eq $Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            $Script:MainFormForm.Elements.ButtonConnect.IsEnabled = $false
            $Script:MainFormForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
            $Script:MainFormForm.Elements.ButtonConnect.ToolTip = "Connect to Omada"
        }
        else {
            if ($Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth" -and
                (
                    [string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxUserName.Text) -or
                    [string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxPassword.Password) -or
                    [string]::IsNullOrWhiteSpace($Script:MainFormForm.Elements.TextBoxEntraIdTenantId.Text)
                )
            ) {
                $Script:MainFormForm.Elements.ButtonConnect.IsEnabled = $false
                $Script:MainFormForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
                $Script:MainFormForm.Elements.ButtonConnect.ToolTip = "Connect to Omada"
            }
            else {
                $Script:MainFormForm.Elements.ButtonConnect.IsEnabled = $true
                if ($Script:ConnectionStatus) {
                    $Script:MainFormForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Disconnect"
                    $Script:MainFormForm.Elements.ButtonConnect.ToolTip = "Disconnect from Omada"
                }
                else {
                    $Script:MainFormForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
                    $Script:MainFormForm.Elements.ButtonConnect.ToolTip = "Connect to Omada"
                }
            }
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
