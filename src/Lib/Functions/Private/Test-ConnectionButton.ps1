function Test-ConnectionButton {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ([string]::IsNullOrEmpty($Script:MainForm.Elements.TextBoxURL.Text) -or $null -eq $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
            $Script:MainForm.Elements.ButtonConnect.IsEnabled = $false
            $Script:MainForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
            $Script:MainForm.Elements.ButtonConnect.ToolTip = "Connect to Omada"
        }
        else {
            if ($Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content -eq "OAuth" -and
                (
                    [string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text) -or
                    [string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password) -or
                    [string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxEntraIdTenantId.Text)
                )
            ) {
                $Script:MainForm.Elements.ButtonConnect.IsEnabled = $false
                $Script:MainForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
                $Script:MainForm.Elements.ButtonConnect.ToolTip = "Connect to Omada"
            }
            else {
                $Script:MainForm.Elements.ButtonConnect.IsEnabled = $true
                if ($Script:ConnectionStatus) {
                    $Script:MainForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Disconnect"
                    $Script:MainForm.Elements.ButtonConnect.ToolTip = "Disconnect from Omada"
                }
                else {
                    $Script:MainForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
                    $Script:MainForm.Elements.ButtonConnect.ToolTip = "Connect to Omada"
                }
            }
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
