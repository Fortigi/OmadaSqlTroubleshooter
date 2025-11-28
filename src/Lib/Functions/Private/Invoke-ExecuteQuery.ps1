function Invoke-ExecuteQuery {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        $ScriptToExecute = "editor.getValue();"

        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $Script:RunTimeData.QueryText = $Script:Task.Result

                    if (![string]::IsNullOrWhiteSpace($Script:RunTimeData.QueryText.ResultAsJson)) {
                        $Script:RunTimeData.QueryText = $Script:RunTimeData.QueryText.ResultAsJson | ConvertFrom-Json
                    }
                    else{
                        $Script:RunTimeData.QueryText = $Script:RunTimeData.QueryText | ConvertFrom-Json
                    }

                    $Private:Result = Save-Query -NewQuery:$false
                    $Script:RunTimeData.RestMethodParam.Uri = "{0}/webservice/jQGridPopulationWebService.asmx/GetPagingData" -f $Script:AppConfig.BaseUrl

                    $Script:RunTimeData.RestMethodParam.Body = @{
                        "dataType"     = "SqlDataProducer"
                        "dataTypeArgs" = @{
                            "targetId" = $Script:AppConfig.CurrentSqlQuery.DoId
                        }
                        "page"         = 1
                        "rows"         = 100000
                        "sidx"         = $null
                        "sord"         = "asc"
                        "_search"      = $false
                        "searchField"  = $null
                        "searchString" = $null
                        "filters"      = $null
                        "searchOper"   = $null
                    }
                    "Body: {0}" -f ($Script:RunTimeData.RestMethodParam.Body | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
                    "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

                    "Retrieve query output, please wait..." | Write-LogOutput
                    $Script:RunTimeData.RestMethodParam.Method = "POST"
                    $Script:RunTimeData.QueryResult = $null
                    $Script:RunTimeData.QueryResult = Invoke-OmadaPSWebRequestWrapper


                    if ($null -ne $Script:RunTimeData.QueryResult -and ($Script:RunTimeData.QueryResult.d.Rows | Measure-Object).Count -le 0) {
                        "Query did not return any results!" | Write-LogOutput -LogType WARNING
                        $Script:MainWindowForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "0 rows"
                        $Script:MainWindowForm.Elements.DataGridQueryResult.ItemsSource = $null
                    }
                    else {
                        $Script:MainWindowForm.Elements.DataGridQueryResult.AutoGenerateColumns = $true
                        try {
                            $Script:MainWindowForm.Elements.DataGridQueryResult.ItemsSource = @($Script:RunTimeData.QueryResult.d.Rows)
                        }
                        catch {
                            #Work-around issue that Omada can return invalid JSON keys.
                            $Script:MainWindowForm.Elements.DataGridQueryResult.ItemsSource = @(($Script:RunTimeData.QueryResult | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10).d.Rows)
                        }
                        "Result:`r`n{0}" -f ($Script:RunTimeData.QueryResult.d.rows | Format-Table -AutoSize | Out-String -Width 10000000 ) | Write-LogOutput -LogType VERBOSE2
                        $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $true
                        $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $true
                        "{0} record(s) retrieved!" -f $Script:RunTimeData.QueryResult.d.Records | Write-LogOutput

                        $Script:MainWindowForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text ("{0:n0} rows" -f [Int]$Script:RunTimeData.QueryResult.d.Records)
                        $Private:Result.Id, $Private:Result.DisplayName | Set-ConfigProperty -Property "CurrentSqlQuery"
                        if ($Private:Result.DisplayName -ne $Script:RunTimeData.CurrentSqlQuery.DisplayName) {
                            "New display name, Current: {0}, New: {1}" -f $Script:RunTimeData.CurrentSqlQuery.DisplayName, $Private:Result.DisplayName | Write-LogOutput -LogType DEBUG
                            "Force update query list" | Write-LogOutput -LogType DEBUG
                            Update-QueryList -ForceRefresh
                            $ComboBoxSelectQueryItem = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" }
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
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonExecuteQueryText | Set-ButtonText -Value "_Execute"
                if ($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }

                if ($null -ne $Script:RunTimeData.StopWatch) {
                    $Script:RunTimeData.StopWatch.Stop()
                    "Elapsed time: {0}" -f $Script:RunTimeData.StopWatch.Elapsed.ToString() | Write-LogOutput -LogType Debug
                    $Script:MainWindowForm.Elements.TextBlockStatusBarQueryTime.Text = $Script:RunTimeData.StopWatch.Elapsed.ToString()
                }
            }
            catch {
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonExecuteQueryText | Set-ButtonText -Value "_Execute"
                if ($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }
                $_.Exception.Message | Write-LogOutput -LogType ERROR
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        if ($null -ne $Script:RunTimeData.StopWatch) {
            $Script:RunTimeData.StopWatch.Stop()
            $Script:MainWindowForm.Elements.TextBlockStatusBarQueryTime.Text = $Script:RunTimeData.StopWatch.Elapsed.ToString()
        }
        $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $true
        $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $true
        $Script:MainWindowForm.Elements.ButtonExecuteQueryText | Set-ButtonText -Value "_Execute"
        if ($null -ne $Script:PopupWindowExecuteQuery) {
            $Script:PopupWindowExecuteQuery.Close()
        }

        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
