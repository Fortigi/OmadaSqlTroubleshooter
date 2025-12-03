function Set-SqlConnectionState {
    [CmdLetBinding()]
    param(
        [bool]$Status = $true
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        Set-SqlQueryFunctionState -Status $Status
        if ($Status) {
            $Script:MainFormForm.Elements.ButtonReset.IsEnabled = $true
            $Script:MainFormForm.Elements.TextBoxUserName.IsEnabled = $false
            $Script:MainFormForm.Elements.TextBoxPassword.IsEnabled = $false
            $Script:MainFormForm.Elements.CheckBoxSavePassword.IsEnabled = $false
            $Script:MainFormForm.Elements.TextBoxAppIdUri.IsEnabled = $false
            $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $false
            $Script:MainFormForm.Elements.TextBoxUrl.IsEnabled = $false
            $Script:MainFormForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Connected"
            $Script:MainFormForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Disconnect"
            $Script:MainFormForm.Elements.TextBlockStatusBarUrl.Text = ([System.Uri]::new($Script:MainFormForm.Elements.TextBoxUrl.Text)).Authority

            if (($Script:MainFormForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -le 1 -or ($Script:MainFormForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1 -and $null -ne $Script:RunTimeConfig.ReconnectStatus -and $Script:RunTimeConfig.ReconnectStatus -ge 2) {
                if ($null -ne $Script:MainFormForm -and $Script:MainFormForm.Definition -and $Script:MainFormForm.Definition.IsVisible) {
                    $ConnectingWindow = Show-PopupWindow -Message "Connecting to Omada..."
                }
                if ($null -ne $Script:Webview.Object.CoreWebView2 -and ($Script:MainFormForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count -lt 8) {
                    Update-DataConnectionList -NotShowPopupWindow
                }
                if ($null -ne $Script:Webview.Object.CoreWebView2 -and ($Script:MainFormForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1) {
                    Update-QueryList -NotShowPopupWindow
                }
                if ($null -ne $ConnectingWindow) {
                    $ConnectingWindow.Close()
                }
            }
            $Script:ConnectionStatus = $true
            $Script:MainFormForm.Definition.Title = "{0} - {1}" -f $Script:RunTimeConfig.ApplicationTitle, ([System.Uri]::new($Script:MainFormForm.Elements.TextBoxUrl.Text)).Authority
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
        }
        else {
            $Script:MainFormForm.Elements.ButtonReset.IsEnabled = $true
            $Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.IsEnabled = $true
            $Script:MainFormForm.Elements.TextBoxUserName.IsEnabled = $true
            $Script:MainFormForm.Elements.TextBoxPassword.IsEnabled = $true
            $Script:MainFormForm.Elements.CheckBoxSavePassword.IsEnabled = $true
            $Script:MainFormForm.Elements.TextBoxAppIdUri.IsEnabled = $true
            $Script:MainFormForm.Elements.TextBoxEntraIdTenantId.IsEnabled = $true
            $Script:MainFormForm.Elements.TextBoxUrl.IsEnabled = $true
            $Script:MainFormForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Disconnected"
            $Script:MainFormForm.Elements.ButtonConnectText | Set-ButtonText -Value "_Connect"
            $Script:MainFormForm.Elements.TextBlockStatusBarUrl | Set-TextBlockText -Text "-"
            $Script:MainFormForm.Elements.TextBlockStatusBarDatabaseName | Set-TextBlockText -Text "-"
            $Script:MainFormForm.Elements.TextBlockStatusBarQueryTime | Set-TextBlockText -Text "00:00:00.0000000"
            $Script:MainFormForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "0 rows"
            $Script:MainFormForm.Definition.Title = $Script:RunTimeConfig.ApplicationTitle

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
