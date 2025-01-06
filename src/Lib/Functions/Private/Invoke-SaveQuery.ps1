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
                    $Script:RunTimeData.QueryText = $Script:Task.Result
                    if (![string]::IsNullOrWhiteSpace($Script:RunTimeData.QueryText.ResultAsJson)) {
                        $Script:RunTimeData.QueryText = $Script:RunTimeData.QueryText.ResultAsJson | ConvertFrom-Json
                    }

                    if ($Script:NewQuery) {
                        "Create new query" | Write-LogOutput -LogType DEBUG

                        $Script:RunTimeData.RestMethodParam.Uri = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$filter=Deleted ne true and NAME eq ''{1}''' -f $Script:AppConfig.BaseUrl, $Script:MainWindowForm.Elements.TextBoxDisplayName.Text
                        "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG
                        "Check if a query with this name already exists" | Write-LogOutput -LogType DEBUG
                        $Script:RunTimeData.RestMethodParam.Body = $Null
                        $Script:RunTimeData.RestMethodParam.Method = "GET"
                        $Script:RunTimeData.RestMethodParam.Body = $null
                        $CheckIfExistResult = Invoke-OmadaPSWebRequestWrapper
                        if ($null -eq $CheckIfExistResult -or ($CheckIfExistResult.Value | Measure-Object).Count -le 0) {
                            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
                            $Script:RunTimeData.RestMethodParam.Method = "POST"
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
                        $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.CurrentSqlQuery.DoId
                        $private:Result = Get-SqlQueryObject
                        $Script:RunTimeData.RestMethodParam.Method = "PUT"
                    }
                    $Script:RunTimeData.RestMethodParam.Body = @{}
                    if ($Script:NewQuery -or ($Script:RunTimeData.CurrentQueryText -ne $Script:RunTimeData.QueryText -or $Script:RunTimeData.QueryText -ne $private:Result.C_QUERY)) {
                        $Script:RunTimeData.RestMethodParam.Body.Add("C_QUERY", $Script:RunTimeData.QueryText)
                        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
                            $Script:RunTimeData.RestMethodParam.Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{Id = $Script:AppConfig.CurrentDataConnection.DoId })
                        }
                    }
                    if ($Script:RunTimeData.CurrentSqlQuery.DisplayName -ne $Script:MainWindowForm.Elements.TextBoxDisplayName.Text) {
                        $Script:RunTimeData.RestMethodParam.Body.Add("NAME", $Script:MainWindowForm.Elements.TextBoxDisplayName.Text)
                    }
                    if (!$Script:NewQuery -and ($Script:RunTimeData.RestMethodParam.Body.Keys | Measure-Object).Count -le 0) {
                        "No changes detected! Saving not needed." | Write-LogOutput -LogType DEBUG
                    }
                    else {
                        "Saving SQL Query: {0}" -f $Script:RunTimeData.QueryText | Write-LogOutput -LogType DEBUG
                        "Body: {0}" -f ($Script:RunTimeData.RestMethodParam.Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
                        "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

                        "Save query" | Write-LogOutput
                        $private:Result = Invoke-OmadaPSWebRequestWrapper

                        if ($null -ne $private:Result -and $Script:NewQuery -or $private:Result.DisplayName -ne $Script:RunTimeData.CurrentSqlQuery.DisplayName) {
                            "Query saved!" | Write-LogOutput
                            if ($Script:NewQuery) {
                                $Script:RunTimeData.CurrentSqlQuery.DoId = $private:Result.Id
                                $Script:RunTimeData.CurrentSqlQuery.DisplayName = $private:Result.Name
                                $private:Result.Id, $private:Result.Name | Invoke-ConfigSetting -Property "CurrentSqlQuery"
                                $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                                $ComboBoxSelectQueryItem.Content = $Script:RunTimeData.CurrentSqlQuery.DoId
                                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                            }
                            else {
                                "New display name, Current: {0}, New: {1}" -f $Script:RunTimeData.CurrentSqlQuery.DisplayName, $private:Result.DisplayName | Write-LogOutput -LogType VERBOSE
                                "Force update query list" | Write-LogOutput -LogType DEBUG
                                Update-QueryList -ForceRefresh
                                $Script:RunTimeData.CurrentSqlQuery.DoId = $Script:AppConfig.CurrentSqlQuery.DoId
                                $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq $Script:RunTimeData.CurrentSqlQuery.DoId }
                                if ($null -eq $ComboBoxSelectQueryItem) {
                                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                                    $ComboBoxSelectQueryItem.Content = $Script:RunTimeData.CurrentSqlQuery.DoId
                                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                                }
                            }
                            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                            $Script:RunTimeData.CurrentSqlQuery.DisplayName = $private:Result.DisplayName
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
