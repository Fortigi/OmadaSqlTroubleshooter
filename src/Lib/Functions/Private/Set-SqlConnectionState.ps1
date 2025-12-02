function Set-SqlConnectionState {
    [CmdLetBinding()]
    param(
        [bool]$Status = $true
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        Set-SqlQueryFunctionState -Status $Status
        if ($Status) {
            $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $true
            $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $false
            $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $false
            $Script:MainWindowForm.Elements.CheckBoxSavePassword.IsEnabled = $false
            $Script:MainWindowForm.Elements.TextBoxAppIdUri.IsEnabled = $false
            $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $false
            $Script:MainWindowForm.Elements.TextBoxUrl.IsEnabled = $false
            $Script:MainWindowForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Connected"
            $Script:MainWindowForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Disconnect"
            $Script:MainWindowForm.Elements.TextBlockStatusBarUrl.Text = ([System.Uri]::new($Script:MainWindowForm.Elements.TextBoxUrl.Text)).Authority

            if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 1 -or ($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1 -and $null -ne $Script:RunTimeConfig.ReconnectStatus -and $Script:RunTimeConfig.ReconnectStatus -ge 2) {
                if ($null -ne $Script:MainWindowForm -and $Script:MainWindowForm.Definition -and $Script:MainWindowForm.Definition.IsVisible) {
                    $ConnectingWindow = Show-PopupWindow -Message "Connecting to Omada..."
                }
                if (($Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -lt 8) {
                    Update-DataConnectionList -NotShowPopupWindow
                }
                if (($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1) {
                    Update-QueryList -NotShowPopupWindow
                }
                if ($null -ne $ConnectingWindow) {
                    $ConnectingWindow.Close()
                }
            }
            $Script:ConnectionStatus = $true
            $Script:MainWindowForm.Definition.Title = "{0} - {1}" -f $Script:RunTimeConfig.ApplicationTitle, ([System.Uri]::new($Script:MainWindowForm.Elements.TextBoxUrl.Text)).Authority
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
        }
        else {
            $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $true
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.IsEnabled = $true
            $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $true
            $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $true
            $Script:MainWindowForm.Elements.CheckBoxSavePassword.IsEnabled = $true
            $Script:MainWindowForm.Elements.TextBoxAppIdUri.IsEnabled = $true
            $Script:MainWindowForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $true
            $Script:MainWindowForm.Elements.TextBoxUrl.IsEnabled = $true
            $Script:MainWindowForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Disconnected"
            $Script:MainWindowForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
            $Script:MainWindowForm.Elements.TextBlockStatusBarUrl | Set-TextBlockText -Text "-"
            $Script:MainWindowForm.Elements.TextBlockStatusBarDatabaseName | Set-TextBlockText -Text "-"
            $Script:MainWindowForm.Elements.TextBlockStatusBarQueryTime | Set-TextBlockText -Text "00:00:00.0000000"
            $Script:MainWindowForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "0 rows"
            $Script:MainWindowForm.Definition.Title = $Script:RunTimeConfig.ApplicationTitle

            $ScriptToExecute = "editor.setValue('');"
            Push-ToEditor -ScriptToExecute $ScriptToExecute

            # $null | Set-ConfigProperty -Property "CurrentDataConnection"
            # $null | Set-ConfigProperty -Property "CurrentSqlQuery"
            $Script:ConnectionStatus = $false
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
