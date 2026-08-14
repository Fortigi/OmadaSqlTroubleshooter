function Reset-Application {
    [CmdLetBinding()]
    param(
        [switch]$SkipTextBoxURL,
        [switch]$SkipAuthentication,
        [switch]$ResetEditor
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Definitions -and $Script:SqlSchemaForm.Definitions.IsVisible) {
            $Script:SqlSchemaForm.Definitions.Close()
        }
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $false
        $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled = $false
        $Script:MainForm.Elements.ButtonOpenOutputFile.IsEnabled = $false

        if (!$SkipTextBoxURL) {
            $Script:MainForm.Elements.TextBoxURL.Text = $null
            $null | Set-ConfigProperty -Property "BaseUrl"
            $null, $null | Set-ConfigProperty -Property "CurrentDataConnection"
            $null, $null | Set-ConfigProperty -Property "CurrentSqlQuery"
            Set-SqlConnectionState -Status $false
        }
        $Script:MainForm.Elements.TextBoxURL.IsEnabled = $true

        if (!$SkipAuthentication) {
            "WebView2" | Set-ConfigProperty -Property "LastAuthentication"
            $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.Items | Where-Object { $_.Content -eq $Script:AppConfig.LastAuthentication }

            if ($Script:MainForm.Elements.TextBoxUserName.IsEnabled) {
                $Script:MainForm.Elements.TextBoxUserName.Text = $null
                $Script:MainForm.Elements.TextBoxUserName.IsEnabled = $true
            }
            if ($Script:MainForm.Elements.TextBoxPassword.IsEnabled) {
                $Script:MainForm.Elements.TextBoxPassword.Password = $null
                $Script:MainForm.Elements.TextBoxPassword.IsEnabled = $true
            }
            if ($Script:MainForm.Elements.CheckboxSavePassword.IsEnabled) {
                $Script:MainForm.Elements.CheckboxSavePassword.IsChecked = $false
                $Script:MainForm.Elements.CheckboxSavePassword.IsEnabled = $true
            }
            if ($Script:MainForm.Elements.TextBoxAppIdUri.IsEnabled) {
                $Script:MainForm.Elements.TextBoxAppIdUri.Text = $null
                $Script:MainForm.Elements.TextBoxAppIdUri.IsEnabled = $false
            }
            if ($Script:MainForm.Elements.TextEntraIdTenantId.IsEnabled) {
                $Script:MainForm.Elements.TextEntraIdTenantId.Text = $null
                $Script:MainForm.Elements.TextEntraIdTenantId.IsEnabled = $false
            }
        }

        if (!$SkipTextBoxURL -and !$SkipAuthentication) {
            Set-SqlQueryFunctionState -Status $false
            "Clear Editor Value because no query is selected!" | Write-LogOutput -LogType DEBUG
            $ScriptToExecute = "window.setEditorValue('');"
            Push-ToEditor -ScriptToExecute $ScriptToExecute
        }

        $Script:MainForm.Elements.ButtonShowOutput.IsEnabled = $false
        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $false

        if ($ResetEditor -and $null -ne $Script:Webview.Object.CoreWebView2) {
            Set-EditorValue
        }
        $Script:RunTimeData.SkipRetryRequest = $false
        $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
