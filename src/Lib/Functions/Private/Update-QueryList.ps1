function Update-QueryList {
    PARAM(
        [switch]$ForceRefresh,
        [switch]$NotShowPopupWindow
    )

    try {
        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        $CurrentTimestamp = Get-Date

        if (($Script:RunTimeData.QueryListCache.QueryList | Measure-Object).Count -eq 0 -or $ForceRefresh -or $Script:RunTimeData.QueryListCache.LastRefresh -lt $CurrentTimestamp.AddSeconds( - $($Script:RunTimeData.QueryListCache.TTL))) {
            $Script:RunTimeData.QueryListCache.QueryList = $null
            "Cleared query cache!" | Write-LogOutput -LogType DEBUG
        }

        "Queries in cache: {0}" -f ($Script:RunTimeData.QueryListCache.QueryList | Measure-Object).Count | Write-LogOutput -LogType DEBUG

        if (($Script:RunTimeData.QueryListCache.QueryList | Measure-Object).Count -le 0) {
            if (!$NotShowPopupWindow) {
                $Script:PopUpWindowQueryRefresh = Show-PopupWindow -Message "Refreshing queries..."
            }
            $Script:RunTimeData.QueryListCache.QueryList = @()
            if ($Script:AppConfig.MyQueriesOnly -and ![string]::IsNullOrWhiteSpace($Script:AppConfig.IdentityUserName)) {
                $SqlQueryViewContents = Get-SqlTroubleShooterView | Where-Object { $_.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryCreatedBy) -eq $Script:AppConfig.IdentityUserName -or $_.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryChangedBy) -eq $Script:AppConfig.IdentityUserName }
            }

            $Script:RunTimeData.RestMethodParam.Uri = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$filter=Deleted ne true and NAME ne ''''' -f $Script:AppConfig.BaseUrl
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG
            "Refresh queries started" | Write-LogOutput
            $Script:RunTimeData.RestMethodParam.Body = $Null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Private:Result = Invoke-OmadaPSWebRequestWrapper

            $SelectedQuery = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content
            "Stored current selected query (if not empty): {0}" -f $SelectedQuery | Write-LogOutput -LogType DEBUG
            $SelectedQueryDisplayName = $Script:MainWindowForm.Elements.TextBoxDisplayName.Text
            "Stored current selected query display name (if not empty): {0}" -f $SelectedQueryDisplayName | Write-LogOutput -LogType DEBUG
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Clear()
            $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $Null

            $ClearQuery = $true
            $Private:Result.value | ForEach-Object {
                $DoIdDisplayName = "{0} - {1}" -f $_.DisplayName, $_.Id
                $Script:RunTimeData.QueryListCache.QueryList += @{
                    $_.Id = $_.DisplayName
                }
                if ($Script:AppConfig.MyQueriesOnly -and $null -ne $SqlQueryViewContents -and $_.Id -notin $SqlQueryViewContents.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryDoId)) {
                    "Skip query {0} because of 'Filter My Queries' is enabled" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                    if ($null -ne $SelectedQuery -and $SelectedQuery -eq $DoIdDisplayName) {
                        "Selected query {0} is filtered, clear selected query" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                        $SelectedQuery = $null
                    }
                }
                else {
                    if ($Script:AppConfig.MyQueriesOnly -and $null -ne $SqlQueryViewContents -and $_.Id -notin $SqlQueryViewContents.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryDoId)) {
                        "Add query {0} because of 'Filter My Queries' is enabled" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                    }
                    else {
                        "Add query {0}" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                    }
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $DoIdDisplayName
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                }
                if ($ClearQuery -and $null -ne $SelectedQuery -and $SelectedQuery -eq $DoIdDisplayName) {
                    "Set query {0} as selected query" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                    $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                    "Set query display name to: {0}" -f $SelectedQueryDisplayName | Write-LogOutput -LogType DEBUG
                    $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $SelectedQueryDisplayName
                    $ClearQuery = $false
                }
            }
            if ($ClearQuery) {
                "Clear editor window because query is not set" | Write-LogOutput -LogType DEBUG
                Set-EditorValue
            }
            if ($null -ne $Script:PopUpWindowQueryRefresh) {
                $Script:PopUpWindowQueryRefresh.Close()
            }
        }
        else {
            "Query list retrieved from cache! Click `"Refresh Queries`" to refresh queries" | Write-LogOutput -LogType INFO
        }

        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.IsEnabled = $True
        $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $True
        $Script:MainWindowForm.Elements.CheckboxMyQueries.IsEnabled = $True
        $Script:MainWindowForm.Elements.ButtonShowSqlSchema.IsEnabled = $true
        $Script:RunTimeData.QueryListCache.LastRefresh = $CurrentTimestamp
        "{0} queries retrieved!" -f ($Script:RunTimeData.QueryListCache.QueryList | Measure-Object).Count | Write-LogOutput

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
