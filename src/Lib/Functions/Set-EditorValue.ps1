function Set-EditorValue {
    try {
        if ($null -ne $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem) {
            "Selected SQL Query object: {0}" -f $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content | Write-LogOutput -LogType DEBUG
            Set-ConfigMultiValue ($Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content) | Invoke-ProcessConfigSettings -Property "SelectedSqlQueryDoId"
            (Split-NameDoIdString -InputString $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content -JoinString " - ").DoId | Invoke-ProcessConfigSettings -Property "SqlQueryDoId"


            if ([string]::IsNullOrWhiteSpace($Script:AppConfig.SqlQueryDoId)) {
                "Omada Url not set or Query not selected. Set correct values to execute queries!" | Write-LogOutput -LogType WARNING
                return
            }
            if (!(Test-ConnectionRequirements)) {
                "Connection requirements are not met" | Write-LogOutput -LogType DEBUG
                return
            }

            $Result = Get-SqlQueryObject
            if ($null -ne $Result) {

                $Script:CurrentSqlQueryDisplayName = $Result.DisplayName
                $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $Result.DisplayName
                Set-ConfigMultiValue ("{0} - {1}" -f $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.DisplayName, $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.Id) | Invoke-ProcessConfigSettings -Property "CurrentDataConnection"
                $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.Id | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionId"
                $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.DisplayName | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionName"


                Set-DataConnection

                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
                $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $true

                if ($null -ne $Script:WebView.CoreWebView2) {

                    $ScriptToExecute = "editor.setValue('{0}');" -f ($Result.C_QUERY -replace "`n", "\n" -replace "`r", "\r" -replace "`t", "\t" -replace "'", "\'")
                    Push-ToEditor -ScriptToExecute $ScriptToExecute
                    $Script:CurrentQueryText = $Result.C_QUERY
                    "Query {0} retrieved!" -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput
                }
            }
        }
        else {
            "Clear Editor Value because no query is selected!" | Write-LogOutput -LogType DEBUG
            $ScriptToExecute = "editor.setValue('');"
            Push-ToEditor -ScriptToExecute $ScriptToExecute
            Reset-Application -SkipTextBoxURL -SkipAuthentication
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
