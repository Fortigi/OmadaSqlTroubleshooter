function Reset-Application {
    PARAM(
        [switch]$SkipTextBoxURL,
        [switch]$SkipAuthentication,
        [switch]$ResetEditor
    )

    try {
        if ($null -ne $Script:SqlSchemaWindow -and $null -ne $Script:SqlSchemaWindow.Definitions -and $Script:SqlSchemaWindow.Definitions.IsVisible) {
            $Script:SqlSchemaWindow.Definitions.Close()
        }
        $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $False
        $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $False
        $Script:MainWindowForm.Elements.ButtonOpenOutputFile.IsEnabled = $False

        if (!$SkipTextBoxURL) {
            $Script:MainWindowForm.Elements.TextBoxURL.Text = $null
            $null | Invoke-ConfigSetting -Property "BaseUrl"
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.SelectedItem = $Null
            $Script:MainWindowForm.Elements.ComboBoxSelectDataConnection.Clear()
            $null, $null | Invoke-ConfigSetting -Property "CurrentDataConnection"
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Clear()
            $Script:MainWindowForm.Elements.CheckboxMyQueries.IsChecked = $False
            $Script:MainWindowForm.Elements.CheckboxMyQueries.IsEnabled = $False
            $null, $null | Invoke-ConfigSetting -Property "CurrentSqlQuery"
        }
        $Script:MainWindowForm.Elements.TextBoxURL.IsEnabled = $True

        if (!$SkipAuthentication) {
            $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $Null
            $null | Invoke-ConfigSetting -Property "LastAuthentication"
            if ($Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled) {
                $Script:MainWindowForm.Elements.TextBoxUserName.Text = $Null
                $Script:MainWindowForm.Elements.TextBoxUserName.IsEnabled = $false
            }
            if ($Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled) {
                $Script:MainWindowForm.Elements.TextBoxPassword.Password = $Null
                $Script:MainWindowForm.Elements.TextBoxPassword.IsEnabled = $false
            }
        }

        if (!$SkipTextBoxURL -and !$SkipAuthentication) {
            # $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $False
            $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $False
            $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $null
        }

        $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $False
        $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $False
        $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $False

        if ($ResetEditor -and $null -ne $Script:Webview.Object.CoreWebView2) {
            Set-EditorValue
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
