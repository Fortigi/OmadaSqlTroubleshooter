function Set-SqlConnectionState {
    [CmdLetBinding()]
    param(
        [bool]$Status = $true
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        Set-SqlQueryFunctionState -Status $Status
        if ($Status) {
            $Script:MainForm.Elements.ButtonReset.IsEnabled = $true
            $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.IsEnabled = $false
            $Script:MainForm.Elements.TextBoxUserName.IsEnabled = $false
            $Script:MainForm.Elements.TextBoxPassword.IsEnabled = $false
            $Script:MainForm.Elements.CheckBoxSavePassword.IsEnabled = $false
            $Script:MainForm.Elements.TextBoxAppIdUri.IsEnabled = $false
            $Script:MainForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $false
            $Script:MainForm.Elements.TextBoxUrl.IsEnabled = $false
            $Script:MainForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Connected"
            $Script:MainForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Disconnect"
            $Script:MainForm.Elements.TextBlockStatusBarUrl.Text = ([System.Uri]::new($Script:MainForm.Elements.TextBoxUrl.Text)).Authority

            if (($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 1 -or ($Script:MainForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1 -and $null -ne $Script:RunTimeConfig.ReconnectStatus -and $Script:RunTimeConfig.ReconnectStatus -ge 2) {
                if ($null -ne $Script:MainForm -and $Script:MainForm.Definition -and $Script:MainForm.Definition.IsVisible) {
                    $ConnectingWindow = Show-PopupWindow -Message "Connecting to Omada..."
                }
                if ($null -ne $Script:Webview.Object.CoreWebView2 -and ($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -lt 8) {
                    Update-DataConnectionList -NotShowPopupWindow
                }
                if ($null -ne $Script:Webview.Object.CoreWebView2 -and ($Script:MainForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1) {
                    Update-QueryList -NotShowPopupWindow
                }
                if ($null -ne $ConnectingWindow) {
                    $ConnectingWindow.Close()
                }
            }
            $Script:ConnectionStatus = $true
            $Script:MainForm.Definition.Title = "{0} - {1}" -f $Script:RunTimeConfig.ApplicationTitle, ([System.Uri]::new($Script:MainForm.Elements.TextBoxUrl.Text)).Authority
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
        }
        else {
            $Script:MainForm.Elements.ButtonReset.IsEnabled = $true
            $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.IsEnabled = $true
            $Script:MainForm.Elements.TextBoxUserName.IsEnabled = $true
            $Script:MainForm.Elements.TextBoxPassword.IsEnabled = $true
            $Script:MainForm.Elements.CheckBoxSavePassword.IsEnabled = $true
            $Script:MainForm.Elements.TextBoxAppIdUri.IsEnabled = $true
            $Script:MainForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $true
            $Script:MainForm.Elements.TextBoxUrl.IsEnabled = $true
            $Script:MainForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Disconnected"
            $Script:MainForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
            $Script:MainForm.Elements.TextBlockStatusBarUrl | Set-TextBlockText -Text "-"
            $Script:MainForm.Elements.TextBlockStatusBarDatabaseName | Set-TextBlockText -Text "-"
            $Script:MainForm.Elements.TextBlockStatusBarQueryTime | Set-TextBlockText -Text "00:00:00.0000000"
            $Script:MainForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "0 rows"
            $Script:MainForm.Definition.Title = $Script:RunTimeConfig.ApplicationTitle

            $ScriptToExecute = "window.setEditorValue('');"
            Push-ToEditor -ScriptToExecute $ScriptToExecute

            # $null | Set-ConfigProperty -Property "CurrentDataConnection"
            # $null | Set-ConfigProperty -Property "CurrentSqlQuery"
            $Script:ConnectionStatus = $false
        }

        # Keep the active tab's stored connection flag and header in sync with the change just made
        # (the header switches between "<name> - <connection> - <tenant>" and "<name> - No
        # connection").
        $ActiveTab = Get-ActiveTabSession
        if ($null -ne $ActiveTab) {
            $ActiveTab.ConnectionStatus = $Script:ConnectionStatus
            Update-TabHeaderTitle -TabSession $ActiveTab
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
