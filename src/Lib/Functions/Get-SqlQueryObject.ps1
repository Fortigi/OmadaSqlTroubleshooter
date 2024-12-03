function Get-SqlQueryObject {

    try {

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.SqlQueryDoId)) {
            $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Invoke-ProcessConfigSettings -Property "BaseUrl"

            [int32]::Parse($Script:AppConfig.SqlQueryDoId) | Invoke-ProcessConfigSettings -Property "SqlQueryDoId"

            "Retrieve current query for SqlQuery DoId: {0}" -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput -LogType DEBUG
            $QueryUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.SqlQueryDoId
            "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG

            "Retrieve query {0}" -f $Script:AppConfig.SqlQueryDoId | Write-LogOutput

            $Body = $Null
            $Method = "GET"
            return Invoke-OmadaPSWebRequestWrapper

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
