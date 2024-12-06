function Get-SqlQueryObject {

    try {

        if(!(Test-ConnectionRequirements)){
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.SqlQueryDoId)) {
            $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Invoke-ProcessConfigSettings -Property "BaseUrl"

            [int32]::Parse($Script:AppConfig.SqlQueryDoId) | Invoke-ProcessConfigSettings -Property "SqlQueryDoId"

            "Retrieve current query for SqlQuery DoId: {0}" -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput -LogType DEBUG
            $QueryUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.SqlQueryDoId
            "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG

            "Retrieve query {0}" -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput

            $Body = $Null
            $Method = "GET"
            try {
                return Invoke-OmadaPSWebRequestWrapper
            }
            catch {
                if ($_.Exception.StatusCode -eq 404) {
                    "Query {0} not found! Clearing current value." -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput -LogType WARNING
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
                    return $null
                }
                else {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR
                }
            }

            "Retrieved object {0}" -f $SqlQueryObject | Write-LogOutput -LogType VERBOSE
        }
        else {
            "SqlQueryDoId is not set! Cannot retrieve Sql query!" | Write-LogOutput -LogType WARNING
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
