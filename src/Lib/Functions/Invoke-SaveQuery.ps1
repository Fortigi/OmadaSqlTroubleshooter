function Invoke-SaveQuery {
    PARAM(
        [switch]$NewQuery
    )


    try {
        $ScriptToExecute = "editor.getValue();"
        $Script:NewQuery = $NewQuery
        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $QueryText = $Script:Task.Result
                    if (![string]::IsNullOrWhiteSpace($QueryText.ResultAsJson)) {
                        $QueryText = $QueryText.ResultAsJson | ConvertFrom-Json
                    }


                    if ($Script:NewQuery) {
                        "Create new query" | Write-LogOutput -LogType DEBUG

                        $QueryUrl = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$filter=Deleted ne true and NAME eq ''{1}''' -f $Script:AppConfig.BaseUrl, $Script:MainWindowForm.Elements.TextBoxDisplayName.Text
                        "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG
                        "Check if a query with this name already exists" | Write-LogOutput -LogType DEBUG
                        $Body = $Null
                        $Method = "GET"
                        $Body = $null
                        $CheckIfExistResult = Invoke-OmadaPSWebRequestWrapper
                        if ($null -eq $CheckIfExistResult -or ($CheckIfExistResult.Value | Measure-Object).Count -le 0) {
                            $QueryUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
                            $Method = "POST"
                        }
                        else {
                            $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $True
                            $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $True
                            "Query with this name already exists!" | Write-LogOutput -LogType ERROR
                            return
                        }
                    }
                    else {
                        "Save existing query" | Write-LogOutput -LogType DEBUG
                        $QueryUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.CurrentSqlQuery.DoId
                        $Result = Get-SqlQueryObject
                        $Method = "PUT"
                    }
                    $Body = @{}
                    if ($Script:NewQuery -or ($Script:CurrentQueryText -ne $QueryText -or $QueryText -ne $Result.C_QUERY)) {
                        $Body.Add("C_QUERY", $QueryText)
                        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
                            $Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{Id = $Script:AppConfig.CurrentDataConnection.DoId })
                        }
                    }
                    if ($Script:CurrentSqlQuery.DisplayName -ne $Script:MainWindowForm.Elements.TextBoxDisplayName.Text) {
                        $Body.Add("NAME", $Script:MainWindowForm.Elements.TextBoxDisplayName.Text)
                    }
                    if (!$Script:NewQuery -and ($Body.Keys | Measure-Object).Count -le 0) {
                        "No changes detected! Saving not needed." | Write-LogOutput -LogType DEBUG
                    }
                    else {
                        "Saving SQL Query: {0}" -f $QueryText | Write-LogOutput -LogType DEBUG
                        "Body: {0}" -f ($Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
                        "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG

                        "Save query" | Write-LogOutput
                        $Result = Invoke-OmadaPSWebRequestWrapper

                        if ($null -ne $Result -and $Script:NewQuery -or $Result.DisplayName -ne $Script:CurrentSqlQuery.DisplayName) {
                            "Query saved!" | Write-LogOutput
                            if ($Script:NewQuery) {
                                $CurrentSqlQuery.DoId = $Result.Id
                                $CurrentSqlQuery.DisplayName = $Result.Name
                                $Result.Id, $Result.Name | Invoke-ConfigSetting -Property "CurrentSqlQuery"
                                $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                                $ComboBoxSelectQueryItem.Content = $CurrentSqlQuery.DoId
                                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                            }
                            else {
                                "New display name, Current: {0}, New: {1}" -f $Script:CurrentSqlQuery.DisplayName, $Result.DisplayName | Write-LogOutput -LogType VERBOSE
                                "Force update query list" | Write-LogOutput -LogType DEBUG
                                Update-QueryList -ForceRefresh
                                $CurrentSqlQuery.DoId = $Script:AppConfig.CurrentSqlQuery.DoId
                                $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq $CurrentSqlQuery.DoId }
                                if ($null -eq $ComboBoxSelectQueryItem) {
                                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                                    $ComboBoxSelectQueryItem.Content = $CurrentSqlQuery.DoId
                                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                                }
                            }
                            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                            $Script:CurrentSqlQuery.DisplayName = $Result.DisplayName
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
