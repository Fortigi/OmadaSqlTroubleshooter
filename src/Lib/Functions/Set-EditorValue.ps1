function Set-EditorValue {
    try {
        if ($null -ne $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem) {
            "Selected SQL Query object: {0}" -f $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content | Write-LogOutput -LogType DEBUG
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content | Invoke-ProcessConfigSettings -Property "SelectedSqlQueryDoId"
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content.Split(" - ")[1].Trim() | Invoke-ProcessConfigSettings -Property "SqlQueryDoId"


            if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.SqlQueryDoId)) {
                "Omada Url not set or Query not selected. Set correct values to execute queries!" | Write-LogOutput -LogType WARNING
            }
            else {

                if ($InvokeOmadaRestMethodParam.ContainsKey("Credential") -and $Null -eq $InvokeOmadaRestMethodParam.Credential) {
                    "Credential is not present, please check credential input!" | Write-LogOutput -LogType ERROR
                }

                $Result = Get-SqlQueryObject

                $Script:CurrentSqlQueryDisplayName = $Result.DisplayName
                $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $Result.DisplayName
                "{0} - {1}" -f $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.DisplayName, $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.Id | Invoke-ProcessConfigSettings -Property "CurrentDataConnection"
                $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.Id | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionId"
                $Result.C_SQLTROUBLESHOOTING_DATACONNECTION.DisplayName | Invoke-ProcessConfigSettings -Property "CurrentDataConnectionName"
                Set-DataConnection

                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $True
                $Script:MainWindowForm.Elements.TextBoxDisplayName.IsEnabled = $True


                if ($null -ne $Script:WebView.CoreWebView2) {

                    $ScriptToExecute = "editor.setValue('{0}');" -f ($Result.C_QUERY -replace "`n", "\n" -replace "`r", "\r" -replace "`t", "\t" -replace "'", "\'")

                    $OnCompletedScriptBlock = {
                        try {
                            if ($Script:Task.Status -eq "RanToCompletion") {
                                "Editor value updated!" | Write-LogOutput -LogType DEBUG
                            }
                            elseif ($Script:Task.Status -eq "Faulted") {
                                "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                            }
                            else {
                                "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                            }
                        }
                        catch {
                            $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR
                        }
                    }

                    Invoke-ExecuteScriptAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
                    $Script:CurrentQueryText = $Result.C_QUERY
                    "Query {0} retrieved!" -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput
                }
            }
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
