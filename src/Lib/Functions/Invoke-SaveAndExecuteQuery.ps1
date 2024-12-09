function Invoke-SaveAndExecuteQuery {


    try {

        if(!(Test-ConnectionRequirements)){
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        $ScriptToExecute = "editor.getValue();"

        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $QueryText = $Script:Task.Result
                    if (![string]::IsNullOrWhiteSpace($QueryText.ResultAsJson)) {
                        $QueryText = $QueryText.ResultAsJson | ConvertFrom-Json
                    }

                    $Result = Get-SqlQueryObject

                    "Executing SQL Query: {0}" -f $QueryText | Write-LogOutput -LogType DEBUG
                    $Body = @{}
                    $QueryUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.CurrentSqlQuery.DoId
                    if ($Script:CurrentQueryText -ne $QueryText -or $QueryText -ne $Result.C_QUERY) {
                        "Update current query for DODI: {0}" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput -LogType DEBUG
                        $Body.Add("C_QUERY", $QueryText)
                        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
                            $Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{Id = $Script:AppConfig.CurrentDataConnection.DoId })
                        }
                    }
                    if ($Script:CurrentSqlQuery.DisplayName -ne $Script:MainWindowForm.Elements.TextBoxDisplayName.Text) {
                        $Body.Add("NAME", $Script:MainWindowForm.Elements.TextBoxDisplayName.Text)
                    }
                    if (($Body.Keys | Measure-Object).Count -le 0) {
                        "No changes detected! Just run query" | Write-LogOutput -LogType DEBUG
                    }
                    else {
                        "Body: {0}" -f ($Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
                        "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG

                        "Save query" | Write-LogOutput
                        $Method = "PUT"
                        $Result = Invoke-OmadaPSWebRequestWrapper
                        "Query saved!" | Write-LogOutput
                    }
                    $QueryUrl = "{0}/webservice/jQGridPopulationWebService.asmx/GetPagingData" -f $Script:AppConfig.BaseUrl

                    $Body = @{
                        "dataType"     = "SqlDataProducer"
                        "dataTypeArgs" = @{
                            "targetId" = $Script:AppConfig.CurrentSqlQuery.DoId
                        }
                        "page"         = 1
                        "rows"         = 100000
                        "sidx"         = $Null
                        "sord"         = "asc"
                        "_search"      = $False
                        "searchField"  = $Null
                        "searchString" = $Null
                        "filters"      = $Null
                        "searchOper"   = $Null
                    }
                    "Body: {0}" -f ($Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
                    "QueryUrl: {0}" -f $QueryUrl | Write-LogOutput -LogType DEBUG

                    "Retrieve query output, please wait..." | Write-LogOutput
                    $Method = "POST"
                    $Script:QueryResult = $null
                    $Script:QueryResult = Invoke-OmadaPSWebRequestWrapper


                    if ($null -ne $Script:QueryResult -and ($Script:QueryResult.d.Rows | Measure-Object).Count -le 0) {
                        "Query did not return any results!" | Write-LogOutput -LogType WARNING
                        $Script:MainWindowForm.Elements.TextBlockRows | Set-TextBlockText -Text "0 rows"
                    }
                    else {
                        $Script:MainWindowForm.Elements.DataGridQueryResult.AutoGenerateColumns = $true
                        try{
                            $Script:MainWindowForm.Elements.DataGridQueryResult.ItemsSource = @($Script:QueryResult.d.Rows)
                        }
                        catch{
                            #Work-around issue that Omada can return invalid JSON keys.
                            $Script:MainWindowForm.Elements.DataGridQueryResult.ItemsSource = @(($Script:QueryResult | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10).d.Rows)
                        }
                        "Result:`r`n{0}" -f ($Script:QueryResult.d.rows | Format-Table -AutoSize | Out-String -Width 10000000 ) | Write-LogOutput
                        $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $True
                        $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $True
                        "{0} record(s) retrieved!" -f $Script:QueryResult.d.Records | Write-LogOutput

                        $Script:MainWindowForm.Elements.TextBlockRows | Set-TextBlockText -Text ("{0:n0} rows" -f [Int]$Script:QueryResult.d.Records)
                        $Result.Id,$Result.DisplayName | Invoke-ConfigSetting -Property "CurrentSqlQuery"
                        if ($Result.DisplayName -ne $Script:CurrentSqlQuery.DisplayName) {
                            "New display name, Current: {0}, New: {1}" -f $Script:CurrentSqlQuery.DisplayName, $Result.DisplayName | Write-LogOutput -LogType DEBUG
                            "Force update query list" | Write-LogOutput -LogType DEBUG
                            Update-QueryList -ForceRefresh
                            $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -eq $Script:AppConfig.CurrentSqlQuery.FullName }
                            if ($null -ne $ComboBoxSelectQueryItem) {
                                $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                                $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                                $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                            }
                            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
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
                $Script:MainWindowForm.Elements.ButtonExecuteQuery | Set-ButtonContent -Content "_Execute Query"
                if($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }

                if ($null -ne $Script:StopWatch) {
                    $Script:StopWatch.Stop()
                    "Elapsed time: {0}" -f $Script:StopWatch.Elapsed.ToString() | Write-LogOutput -Debug
                    $Script:MainWindowForm.Elements.TextBlockQueryTime.Text = $Script:StopWatch.Elapsed.ToString()
                }
            }
            catch {
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonExecuteQuery | Set-ButtonContent -Content "_Execute Query"
                if($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }
                $_.Exception.Message | Write-LogOutput -LogType ERROR
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        if ($null -ne $Script:StopWatch) {
            $Script:StopWatch.Stop()
            $Script:MainWindowForm.Elements.TextBlockQueryTime.Text = $Script:StopWatch.Elapsed.ToString()
        }
        $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $True
        $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $True
        $Script:MainWindowForm.Elements.ButtonExecuteQuery | Set-ButtonContent -Content "_Execute Query"
        if($null -ne $Script:PopupWindowExecuteQuery) {
            $Script:PopupWindowExecuteQuery.Close()
        }

        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
