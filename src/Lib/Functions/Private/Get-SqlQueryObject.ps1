function Get-SqlQueryObject {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }
        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId) -and $Script:AppConfig.CurrentSqlQuery.DoId -gt 0) {
            $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Set-ConfigProperty -Property "BaseUrl"

            "Retrieve current query for SqlQuery DoId: {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.CurrentSqlQuery.DoId
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Retrieve query {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput

            $Script:RunTimeData.RestMethodParam.Body = $null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            try {
                return Invoke-OmadaPSWebRequestWrapper
            }
            catch {
                if ($_.TargetObject?.Exception?.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
                    "Query {0} not found! Clearing current value." -f $Script:AppConfig.CurrentSqlQuery.FullName | Write-LogOutput -LogType WARNING -SkipDialog
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $null
                    $null, $null | Set-ConfigProperty -Property "CurrentSqlQuery"
                    return $null
                }
                elseif ($_.TargetObject?.Exception?.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $null
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                    return $null
                }
                elseif ($_.TargetObject?.Exception?.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $null
                    $_.Exception.Message | Write-LogOutput -LogType WARNING
                    return $null
                }
                else {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

            "Retrieved object { 0 }" -f $Script:RunTimeData.SqlQueryObject | Write-LogOutput -LogType VERBOSE
        }
        else {
            "CurrentSqlQuery DoId is not set! Cannot retrieve Sql query!" | Write-LogOutput -LogType WARNING -SkipDialog
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
