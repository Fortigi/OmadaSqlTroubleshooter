function Invoke-SaveQuery {


    try {
        $ScriptToExecute = "editor.getValue();"

        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $QueryText = $Script:Task.Result
                    if (![string]::IsNullOrWhiteSpace($QueryText.ResultAsJson)) {
                        $QueryText = $QueryText.ResultAsJson | ConvertFrom-Json
                    }

                    $Result = Get-SqlQueryObject

                    $Body = @{}
                    $QueryUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.SqlQueryDoId
                    if ($Script:CurrentQueryText -ne $QueryText -or $QueryText -ne $Result.C_QUERY) {
                        "Update current query for DODI: {0}" -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput -LogType DEBUG
                        $Body.Add("C_QUERY", $QueryText)
                        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnectionId)) {
                            $Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{Id = $Script:AppConfig.CurrentDataConnectionId })
                        }
                    }
                    if ($Script:CurrentSqlQueryDisplayName -ne $Script:MainWindowForm.Elements.TextBoxDisplayName.Text) {
                        $Body.Add("NAME", $Script:MainWindowForm.Elements.TextBoxDisplayName.Text)
                    }
                    if (($Body.Keys | Measure-Object).Count -le 0) {
                        "No changes detected! Saving not needed." | Write-LogOutput -LogType DEBUG
                    }
                    else {
                        "Saving SQL Query: {0}" -f $QueryText | Write-LogOutput -LogType DEBUG
                        "Body: {0}" -f ($Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
                        "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG

                        "Save query" | Write-LogOutput
                        $Method = "PUT"
                        $Result = Invoke-OmadaPSWebRequestWrapper
                        "Query saved!" | Write-LogOutput

                        "{0} - {1}" -f $Result.DisplayName, $Result.Id | Invoke-ProcessConfigSettings -Property "SelectedSqlQueryDoId"
                        if ($Result.DisplayName -ne $Script:CurrentSqlQueryDisplayName) {
                            "New display name, Current: {0}, New: {1}" -f $Script:CurrentSqlQueryDisplayName, $Result.DisplayName | Write-LogOutput -LogType VERBOSE
                            Update-QueryList -ForceRefresh
                            $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq $Script:AppConfig.SelectedSqlQueryDoId }
                            if ($null -ne $ComboBoxSelectQueryItem) {
                                $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                                $ComboBoxSelectQueryItem.Content = $Script:AppConfig.SelectedSqlQueryDoId
                                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                            }
                            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                            $Script:CurrentSqlQueryDisplayName = $Result.DisplayName
                        }
                    }
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $True
            }
            catch {
                $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
