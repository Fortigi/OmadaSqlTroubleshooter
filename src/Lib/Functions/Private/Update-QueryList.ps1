function Update-QueryList {
    [CmdLetBinding()]
    param(
        [switch]$ForceRefresh,
        [switch]$NotShowPopupWindow
    )

    try {

        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip reconnect" | Write-LogOutput -LogType DEBUG
            return
        }

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
            if ($Script:AppConfig.MyCreatedQueriesOnly -and $Script:AppConfig.MyUpdatedQueriesOnly -and ![string]::IsNullOrWhiteSpace($Script:AppConfig.IdentityUserName)) {
                $SqlQueryViewContents = Get-SqlTroubleShooterView | Where-Object { $_.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryCreatedBy) -eq $Script:AppConfig.IdentityUserName -or $_.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryChangedBy) -eq $Script:AppConfig.IdentityUserName }
            }
            elseif ($Script:AppConfig.MyCreatedQueriesOnly -and !$Script:AppConfig.MyUpdatedQueriesOnly -and ![string]::IsNullOrWhiteSpace($Script:AppConfig.IdentityUserName)) {
                $SqlQueryViewContents = Get-SqlTroubleShooterView | Where-Object { $_.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryCreatedBy) -eq $Script:AppConfig.IdentityUserName -eq $Script:AppConfig.IdentityUserName }
            }
            elseif (!$Script:AppConfig.MyCreatedQueriesOnly -and $Script:AppConfig.MyUpdatedQueriesOnly -and ![string]::IsNullOrWhiteSpace($Script:AppConfig.IdentityUserName)) {
                $SqlQueryViewContents = Get-SqlTroubleShooterView | Where-Object { $_.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryChangedBy) -eq $Script:AppConfig.IdentityUserName }
            }

            $Script:RunTimeData.RestMethodParam.Uri = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$orderby=DisplayName,NAME&$filter=Deleted ne true' -f $Script:AppConfig.BaseUrl
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG
            "Refresh queries started" | Write-LogOutput
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Private:Result = Invoke-OmadaPSWebRequestWrapper

            $SelectedQuery = $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem.Content
            "Stored current selected query (if not empty): {0}" -f $SelectedQuery | Write-LogOutput -LogType DEBUG
            $SelectedQueryDisplayName = $Script:MainForm.Elements.TextBoxDisplayName.Text
            "Stored current selected query display name (if not empty): {0}" -f $SelectedQueryDisplayName | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Clear()
            $Script:MainForm.Elements.TextBoxDisplayName.Text = $null

            $ClearQuery = $true
            if ($null -ne $Private:Result -and $Private:Result -is [System.Management.Automation.ErrorRecord]) {
                Set-SqlConnectionState -Status $false
                $Private:Result.Exception.Message | Write-LogOutput -LogType ERROR
                return
            }

            $Private:Result.value | ForEach-Object {
                $DoIdDisplayName = "{0} - {1}" -f $_.DisplayName, $_.Id
                $Script:RunTimeData.QueryListCache.QueryList += @{
                    $_.Id = $_.DisplayName
                }
                if (($Script:AppConfig.MyCreatedQueriesOnly -or $Script:AppConfig.MyUpdatedQueriesOnly) -and $null -ne $SqlQueryViewContents -and $_.Id -notin $SqlQueryViewContents.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryDoId)) {
                    "Skip query {0} because of 'Filter My Queries' is enabled (MyCreatedQueriesOnly: {1}, MyUpdatedQueriesOnly: {2})" -f $DoIdDisplayName, $Script:AppConfig.MyCreatedQueriesOnly, $Script:AppConfig.MyUpdatedQueriesOnly | Write-LogOutput -LogType DEBUG
                    if ($null -ne $SelectedQuery -and $SelectedQuery -eq $DoIdDisplayName) {
                        "Selected query {0} is filtered, clear selected query" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                        $SelectedQuery = $null
                    }
                }
                else {
                    if (($Script:AppConfig.MyCreatedQueriesOnly -or $Script:AppConfig.MyUpdatedQueriesOnly) -and $null -ne $SqlQueryViewContents -and $_.Id -notin $SqlQueryViewContents.$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryDoId)) {
                        "Add query {0} because of 'Filter My Queries' is enabled (MyCreatedQueriesOnly: {1}, MyUpdatedQueriesOnly: {2})" -f $DoIdDisplayName, $Script:AppConfig.MyCreatedQueriesOnly, $Script:AppConfig.MyUpdatedQueriesOnly | Write-LogOutput -LogType DEBUG
                    }
                    else {
                        "Add query {0}" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                    }
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $DoIdDisplayName
                    $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                }
                if ($ClearQuery -and $null -ne $SelectedQuery -and $SelectedQuery -eq $DoIdDisplayName) {
                    "Set query {0} as selected query" -f $DoIdDisplayName | Write-LogOutput -LogType DEBUG
                    $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                    "Set query display name to: {0}" -f $SelectedQueryDisplayName | Write-LogOutput -LogType DEBUG
                    $Script:MainForm.Elements.TextBoxDisplayName.Text = $SelectedQueryDisplayName
                    $ClearQuery = $false
                }
            }
            if ($ClearQuery) {
                "Clear editor because query is not set" | Write-LogOutput -LogType DEBUG
                Set-EditorValue
            }
            if ($null -ne $Script:PopUpWindowQueryRefresh) {
                $Script:PopUpWindowQueryRefresh.Close()
            }
        }
        else {
            "Query list retrieved from cache! Click `"Refresh`" to refresh queries" | Write-LogOutput -LogType INFO
        }
        # $ComboBoxSelectedQueryItem = $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem
        # $ComboBoxSelectQueryItems = $Script:MainForm.Elements.ComboBoxSelectQuery.Items | Sort-Object
        # $Script:MainForm.Elements.ComboBoxSelectQuery.Items?.Clear()
        # foreach ($Item in $ComboBoxSelectQueryItems) {
        #     $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($Item) | Out-Null
        # }
        # if ($null -ne $ComboBoxSelectedQueryItem) {
        #     $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $Script:MainForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq $ComboBoxSelectedQueryItem.Content }
        # }

        $Script:MainForm.Elements.ComboBoxSelectQuery.IsEnabled = $true
        $Script:MainForm.Elements.ButtonRefreshQueries.IsEnabled = $true
        $Script:MainForm.Elements.CheckboxMyCreatedQueries.IsEnabled = $true
        $Script:MainForm.Elements.CheckboxMyUpdatedQueries.IsEnabled = $true
        $Script:MainForm.Elements.ButtonShowSqlSchema.IsEnabled = $true
        $Script:RunTimeData.QueryListCache.LastRefresh = $CurrentTimestamp
        "{0} queries retrieved!" -f ($Script:RunTimeData.QueryListCache.QueryList | Measure-Object).Count | Write-LogOutput

    }
    catch {
        $_
    }
}
