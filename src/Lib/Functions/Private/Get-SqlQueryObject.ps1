function Get-SqlQueryObject {
    try {
        if(!(Test-ConnectionRequirements)){
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }
        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
            $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Invoke-ConfigSetting -Property "BaseUrl"

            "Retrieve current query for SqlQuery DoId: {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.CurrentSqlQuery.DoId
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Retrieve query {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput

            $Script:RunTimeData.RestMethodParam.Body = $Null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            try {
                return Invoke-OmadaPSWebRequestWrapper
            }
            catch {
                if ($_.Exception.StatusCode -eq 404) {
                    "Query {0} not found! Clearing current value." -f $Script:AppConfig.CurrentSqlQuery.FullName | Write-LogOutput -LogType WARNING
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
                    return $null
                }
                else {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR
                }
            }

            "Retrieved object {0}" -f $Script:RunTimeData.SqlQueryObject | Write-LogOutput -LogType VERBOSE
        }
        else {
            "CurrentSqlQuery DoId is not set! Cannot retrieve Sql query!" | Write-LogOutput -LogType WARNING
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
