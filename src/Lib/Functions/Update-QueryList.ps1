function Update-QueryList {

    PARAM(
        [switch]$ForceRefresh
    )

    try {
        $CurrentTimestamp = Get-Date

        if (($Script:QueryListCache.QueryList | Measure-Object).Count -eq 0 -or $ForceRefresh -or $Script:QueryListCache.LastRefresh -lt $CurrentTimestamp.AddSeconds( - $($Script:QueryListCache.TTL))) {
            $Script:QueryListCache.QueryList = $null
            "Refresh queries!" | Write-LogOutput -LogType DEBUG
        }

        if (($Script:QueryListCache.QueryList | Measure-Object).Count -eq 0) {

            if ($Script:AppConfig.MyQueriesOnly -and ![string]::IsNullOrWhiteSpace($Script:AppConfig.IdentityUserName)) {
                $SqlQueryViewContents = Get-SqlTroubleShooterView | Where-Object { $_.$($SqlQueryCreatedByAttribute) -eq $Script:AppConfig.IdentityUserName -or $_.$($SqlQueryChangedByAttribute) -eq $Script:AppConfig.IdentityUserName }
            }

            $QueryUrl = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$filter=Deleted ne true and NAME ne ''''' -f $Script:AppConfig.BaseUrl
            "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG
            "Refresh queries started" | Write-LogOutput
            $Body = $Null
            $Method = "GET"
            $Body = $null
            $Result = Invoke-OmadaPSWebRequestWrapper


            $Result.value | ForEach-Object {
                $DOIDDisplayName = "{0} - {1}" -f $_.DisplayName, $_.Id
                if ($Script:AppConfig.MyQueriesOnly -and $null -ne $SqlQueryViewContents -and $_.Id -notin $SqlQueryViewContents.$SqlQueryDoIdAttribute) {
                    "Skip query {0} - {1} because of 'Filter My Queries' is enabled" -f $_.Id, $_.DisplayName | Write-LogOutput -LogType DEBUG

                    if ($DOIDDisplayName -in $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Content) {
                        $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq $DOIDDisplayName }
                        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Remove($ComboBoxSelectQueryItem) | Out-Null
                    }
                }
                else {
                    $DOIDDisplayName = "{0} - {1}" -f $_.DisplayName, $_.Id
                    if ($DOIDDisplayName -notin $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Content) {
                        $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                        $ComboBoxSelectQueryItem.Content = $DOIDDisplayName
                        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                    }
                }
            }
            $Script:QueryListCache.QueryList = $Result.value
            $Script:QueryListCache.LastRefresh = $CurrentTimestamp
        }
        else {
            "Query list retrieved from cache! Click `"Refresh Queries`" to refresh queries" | Write-LogOutput -LogType INFO
        }

        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $True
        $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $True
        "{0} queries retrieved!" -f ($Result.Value | Measure-Object).Count | Write-LogOutput

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
