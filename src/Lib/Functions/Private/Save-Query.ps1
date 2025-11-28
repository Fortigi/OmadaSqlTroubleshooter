function Save-Query {
    [CmdLetBinding()]
    PARAM(
        [switch]$NewQuery
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if ($NewQuery) {
            "Create new query" | Write-LogOutput -LogType DEBUG

            $Script:RunTimeData.RestMethodParam.Uri = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$filter=Deleted ne true and NAME eq ''{1}''' -f $Script:AppConfig.BaseUrl, $Script:MainWindowForm.Elements.TextBoxDisplayName.Text
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG
            "Check if a query with this name already exists" | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $Script:RunTimeData.RestMethodParam.Body = $null
            $CheckIfExistResult = Invoke-OmadaPSWebRequestWrapper
            if ($null -eq $CheckIfExistResult -or ($CheckIfExistResult.Value | Measure-Object).Count -le 0) {
                $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
                $Script:RunTimeData.RestMethodParam.Method = "POST"
            }
            else {
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $true
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
        if ($NewQuery -or ($Script:RunTimeData.CurrentQueryText -ne $Script:RunTimeData.QueryText -or $Script:RunTimeData.QueryText -ne $private:Result.C_QUERY)) {
            $Script:RunTimeData.RestMethodParam.Body.Add("C_QUERY", $Script:RunTimeData.QueryText)
            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
                $Script:RunTimeData.RestMethodParam.Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{Id = $Script:AppConfig.CurrentDataConnection.DoId })
            }
        }
        if ($Script:RunTimeData.CurrentSqlQuery.DisplayName -ne $Script:MainWindowForm.Elements.TextBoxDisplayName.Text) {
            $Script:RunTimeData.RestMethodParam.Body.Add("NAME", $Script:MainWindowForm.Elements.TextBoxDisplayName.Text)
        }
        if (!$NewQuery -and ($Script:RunTimeData.RestMethodParam.Body.Keys | Measure-Object).Count -le 0) {
            "No changes detected! Saving not needed." | Write-LogOutput -LogType DEBUG
            return $private:Result
        }
        else {

            "Saving SQL Query: {0}" -f $Script:RunTimeData.QueryText | Write-LogOutput -LogType DEBUG
            "Body: {0}" -f ($Script:RunTimeData.RestMethodParam.Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Save query" | Write-LogOutput
            $private:Result = Invoke-OmadaPSWebRequestWrapper

            if ($null -ne $private:Result -and $NewQuery -or $private:Result.DisplayName -ne $Script:RunTimeData.CurrentSqlQuery.DisplayName) {
                "Query saved!" | Write-LogOutput
                if ($NewQuery) {
                    $Script:RunTimeData.CurrentSqlQuery.DoId = $private:Result.Id
                    $Script:RunTimeData.CurrentSqlQuery.DisplayName = $private:Result.Name
                    $private:Result.Id, $private:Result.Name | Set-ConfigProperty -Property "CurrentSqlQuery"
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                }
                else {
                    "New display name, Current: {0}, New: {1}" -f $Script:RunTimeData.CurrentSqlQuery.DisplayName, $private:Result.DisplayName | Write-LogOutput -LogType VERBOSE
                    "Force update query list" | Write-LogOutput -LogType DEBUG
                    Update-QueryList -ForceRefresh
                    $Script:RunTimeData.CurrentSqlQuery.DoId = $Script:AppConfig.CurrentSqlQuery.DoId
                    $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" }
                    if ($null -eq $ComboBoxSelectQueryItem) {
                        $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                        $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                    }
                }
                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                $Script:RunTimeData.CurrentSqlQuery.DisplayName = $private:Result.DisplayName
                return $private:Result
            }
            else {
                return $private:Result
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
