function Reset-Application {
    [CmdLetBinding()]
    param(
        [switch]$SkipTextBoxURL,
        [switch]$SkipAuthentication,
        [switch]$ResetEditor
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:SqlSchemaWindow -and $null -ne $Script:SqlSchemaWindow.Definitions -and $Script:SqlSchemaWindow.Definitions.IsVisible) {
            $Script:SqlSchemaWindow.Definitions.Close()
        }
        $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonOpenOutputFile.IsEnabled = $false

        if (!$SkipTextBoxURL) {
            $Script:MainWindowForm.Elements.TextBoxURL.Text = $null
            $null | Set-ConfigProperty -Property "BaseUrl"
            $null, $null | Set-ConfigProperty -Property "CurrentDataConnection"
            $null, $null | Set-ConfigProperty -Property "CurrentSqlQuery"
            Set-SqlConnectionState -Status $false
        }
        $Script:MainWindowForm.Elements.TextBoxURL.IsEnabled = $true

        if (!$SkipAuthentication) {
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $null
            $null | Set-ConfigProperty -Property "LastAuthentication"
            if ($Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled) {
                $Script:MainWindowForm.Elements.TextBoxUserName.Text = $null
                $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $false
            }
            if ($Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled) {
                $Script:MainWindowForm.Elements.TextBoxPassword.Password = $null
                $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $false
            }
            if ($Script:MainWindowForm.Elements.CheckboxSavePassword.IsEnabled) {
                $Script:MainWindowForm.Elements.CheckboxSavePassword.IsChecked = $false
                $Script:MainWindowForm.Elements.CheckboxSavePassword.IsEnabled = $false
            }
            if ($Script:MainWindowForm.Elements.TextBoxAppIdUri.IsEnabled) {
                $Script:MainWindowForm.Elements.TextBoxAppIdUri.Text = $null
                $Script:MainWindowForm.Elements.TextBoxAppIdUri.IsEnabled = $false
            }
            if ($Script:MainWindowForm.Elements.TextEntraIdTenantId.IsEnabled) {
                $Script:MainWindowForm.Elements.TextEntraIdTenantId.Text = $null
                $Script:MainWindowForm.Elements.TextEntraIdTenantId.IsEnabled = $false
            }
        }

        if (!$SkipTextBoxURL -and !$SkipAuthentication) {
            Set-SqlQueryFunctionState -Status $false
            "Clear Editor Value because no query is selected!" | Write-LogOutput -LogType DEBUG
            $ScriptToExecute = "editor.setValue('');"
            Push-ToEditor -ScriptToExecute $ScriptToExecute
        }

        $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $false
        $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $false

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
