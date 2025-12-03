function Reset-Application {
    [CmdLetBinding()]
    param(
        [switch]$SkipTextBoxURL,
        [switch]$SkipAuthentication,
        [switch]$ResetEditor
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Definitions -and $Script:SqlSchemaForm.Definitions.IsVisible) {
            $Script:SqlSchemaForm.Definitions.Close()
        }
        $Script:MainFormForm.Elements.ButtonExecuteQuery.IsEnabled = $false
        $Script:MainFormForm.Elements.ButtonSaveOutputFile.IsEnabled = $false
        $Script:MainFormForm.Elements.ButtonOpenOutputFile.IsEnabled = $false

        if (!$SkipTextBoxURL) {
            $Script:MainFormForm.Elements.TextBoxURL.Text = $null
            $null | Set-ConfigProperty -Property "BaseUrl"
            $null, $null | Set-ConfigProperty -Property "CurrentDataConnection"
            $null, $null | Set-ConfigProperty -Property "CurrentSqlQuery"
            Set-SqlConnectionState -Status $false
        }
        $Script:MainFormForm.Elements.TextBoxURL.IsEnabled = $true

        if (!$SkipAuthentication) {
            "WebView2" | Set-ConfigProperty -Property "LastAuthentication"
            $Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $Script:MainFormForm.Elements.ComboBoxSelectAuthenticationOption.Items | Where-Object { $_.Content -eq $Script:AppConfig.LastAuthentication }

            if ($Script:MainFormForm.Elements.TextBoxUserName.IsEnabled) {
                $Script:MainFormForm.Elements.TextBoxUserName.Text = $null
                $Script:MainFormForm.Elements.TextBoxUserName.IsEnabled = $true
            }
            if ($Script:MainFormForm.Elements.TextBoxPassword.IsEnabled) {
                $Script:MainFormForm.Elements.TextBoxPassword.Password = $null
                $Script:MainFormForm.Elements.TextBoxPassword.IsEnabled = $true
            }
            if ($Script:MainFormForm.Elements.CheckboxSavePassword.IsEnabled) {
                $Script:MainFormForm.Elements.CheckboxSavePassword.IsChecked = $false
                $Script:MainFormForm.Elements.CheckboxSavePassword.IsEnabled = $true
            }
            if ($Script:MainFormForm.Elements.TextBoxAppIdUri.IsEnabled) {
                $Script:MainFormForm.Elements.TextBoxAppIdUri.Text = $null
                $Script:MainFormForm.Elements.TextBoxAppIdUri.IsEnabled = $false
            }
            if ($Script:MainFormForm.Elements.TextEntraIdTenantId.IsEnabled) {
                $Script:MainFormForm.Elements.TextEntraIdTenantId.Text = $null
                $Script:MainFormForm.Elements.TextEntraIdTenantId.IsEnabled = $false
            }
        }

        if (!$SkipTextBoxURL -and !$SkipAuthentication) {
            Set-SqlQueryFunctionState -Status $false
            "Clear Editor Value because no query is selected!" | Write-LogOutput -LogType DEBUG
            $ScriptToExecute = "editor.setValue('');"
            Push-ToEditor -ScriptToExecute $ScriptToExecute
        }

        $Script:MainFormForm.Elements.ButtonShowOutput.IsEnabled = $false
        $Script:MainFormForm.Elements.ButtonSaveQuery.IsEnabled = $false

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
