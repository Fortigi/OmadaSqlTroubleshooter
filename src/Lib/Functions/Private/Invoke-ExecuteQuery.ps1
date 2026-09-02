function Invoke-ExecuteQuery {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        $ScriptToExecute = "(function() { var fullText = editor.getValue(); var sel = editor.getSelection(); var hasSelection = sel && !sel.isEmpty(); var selectedText = hasSelection ? editor.getModel().getValueInRange(sel) : null; return { fullText: fullText, selectedText: selectedText }; })();"

        $OnCompletedScriptBlock = {
            $Private:TempQueryDoId = $null
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $Private:EditorData = $Script:Task.Result | ConvertFrom-Json
                    $Script:RunTimeData.QueryText = $Private:EditorData.fullText
                    $Private:SelectionText = $Private:EditorData.selectedText

                    # Client-side syntax gate (issue #61). Checks the text that will actually run -
                    # the selection when there is one - refreshes the editor's markers from it, and
                    # asks once before spending a round trip on a batch SQL Server will reject
                    # before it touches a table. It NEVER blocks: parser version and server version
                    # can legitimately disagree, so declining is a choice, not an error.
                    $Private:TextToValidate = $Private:EditorData.fullText
                    if (![string]::IsNullOrWhiteSpace($Private:SelectionText)) {
                        $Private:TextToValidate = $Private:SelectionText
                    }

                    $Private:ValidationSetting = Get-SqlValidationSetting
                    if ($Private:ValidationSetting.Enabled) {
                        $Private:SyntaxResult = Get-SqlSyntaxDiagnostic -SqlText $Private:TextToValidate -ParserVersion $Private:ValidationSetting.ParserVersion
                        if ($Private:SyntaxResult.Status -eq "Ok") {
                            Invoke-ExecuteScriptAsync -ScriptToExecute (ConvertTo-EditorDiagnosticScript -Diagnostic $Private:SyntaxResult.Diagnostic)

                            if (($Private:SyntaxResult.Diagnostic | Measure-Object).Count -gt 0 -and $Private:ValidationSetting.WarnOnExecuteWithErrors) {
                                "Query has {0} syntax diagnostic(s); asking before executing." -f ($Private:SyntaxResult.Diagnostic | Measure-Object).Count | Write-LogOutput -LogType DEBUG
                                $Private:Confirmed = Open-ChoiceForm -Title "Syntax errors" -Message (Get-SqlSyntaxWarningMessage -Diagnostic $Private:SyntaxResult.Diagnostic) -LeftButtonText "Execute anyway" -RightButtonText "Cancel"
                                if ($Private:Confirmed -ne $true) {
                                    "Execution cancelled by the user after the syntax check." | Write-LogOutput -LogType DEBUG
                                    $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
                                    $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
                                    if ($null -ne $Script:PopupWindowExecuteQuery) {
                                        $Script:PopupWindowExecuteQuery.Close()
                                    }
                                    if ($null -ne $Script:RunTimeData.StopWatch) {
                                        $Script:RunTimeData.StopWatch.Stop()
                                    }
                                    return
                                }
                            }
                        }
                    }

                    $Private:Result = Save-Query -NewQuery:$false

                    $Private:ExecutionTargetId = $Script:AppConfig.CurrentSqlQuery.DoId
                    if (![string]::IsNullOrWhiteSpace($Private:SelectionText)) {
                        "Execute selection mode: creating temporary query object" | Write-LogOutput -LogType DEBUG
                        $Private:TempQueryDoId = New-TemporarySqlQueryObject -QueryText $Private:SelectionText
                        if ($null -ne $Private:TempQueryDoId) {
                            $Private:ExecutionTargetId = $Private:TempQueryDoId
                        }
                        else {
                            "Failed to create temporary query object for selection execution." | Write-LogOutput -LogType ERROR
                            return
                        }
                    }

                    $Script:RunTimeData.RestMethodParam.Uri = "{0}/webservice/jQGridPopulationWebService.asmx/GetPagingData" -f $Script:AppConfig.BaseUrl

                    $Script:RunTimeData.RestMethodParam.Body = @{
                        "dataType"     = "SqlDataProducer"
                        "dataTypeArgs" = @{
                            "targetId" = $Private:ExecutionTargetId
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
                    "Body: {0}" -f (ConvertTo-RedactedLogString -InputObject $Script:RunTimeData.RestMethodParam.Body -ShapeOnly) | Write-LogOutput -LogType VERBOSE
                    "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

                    "Retrieve query output, please wait..." | Write-LogOutput
                    $Script:RunTimeData.RestMethodParam.Method = "POST"
                    $Script:RunTimeData.QueryResult = $null
                    $Script:RunTimeData.QueryResult = Invoke-OmadaPSWebRequestWrapper

                    if ($null -ne $Private:TempQueryDoId) {
                        Remove-SqlQueryObject -DoId $Private:TempQueryDoId
                        $Private:TempQueryDoId = $null
                    }

                    $Script:DataGridQueryResultColumnSelectionAnchor = $null

                    if ($null -ne $Script:RunTimeData.QueryResult -and ($Script:RunTimeData.QueryResult.d.Rows | Measure-Object).Count -le 0) {
                        "Query did not return any results!" | Write-LogOutput -LogType WARNING
                        $Script:MainForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text "0 rows"
                        $Script:MainForm.Elements.DataGridQueryResult.ItemsSource = $null
                    }
                    else {
                        $Script:MainForm.Elements.DataGridQueryResult.AutoGenerateColumns = $true
                        try {
                            $Script:MainForm.Elements.DataGridQueryResult.ItemsSource = @($Script:RunTimeData.QueryResult.d.Rows)
                        }
                        catch {
                            #Work-around issue that Omada can return invalid JSON keys.
                            $Script:MainForm.Elements.DataGridQueryResult.ItemsSource = @(($Script:RunTimeData.QueryResult | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10).d.Rows)
                        }
                        "Result: {0}" -f (Get-LogResultShape -InputObject $Script:RunTimeData.QueryResult.d.rows) | Write-LogOutput -LogType VERBOSE2
                        $Script:MainForm.Elements.ButtonShowOutput.IsEnabled = $true
                        $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled = $true
                        "{0} record(s) retrieved!" -f $Script:RunTimeData.QueryResult.d.Records | Write-LogOutput

                        $Script:MainForm.Elements.TextBlockStatusBarRows | Set-TextBlockText -Text ("{0:n0} rows" -f [Int]$Script:RunTimeData.QueryResult.d.Records)
                        $Private:Result.Id, $Private:Result.DisplayName | Set-ConfigProperty -Property "CurrentSqlQuery"
                        if ($Private:Result.DisplayName -ne $Script:RunTimeData.CurrentSqlQuery.DisplayName) {
                            "New display name, Current: {0}, New: {1}" -f $Script:RunTimeData.CurrentSqlQuery.DisplayName, $Private:Result.DisplayName | Write-LogOutput -LogType DEBUG
                            "Force update query list" | Write-LogOutput -LogType DEBUG
                            Update-QueryList -ForceRefresh
                            if ($null -ne $ComboBoxSelectQueryItem) {
                                $ComboBoxSelectQueryItem = $Script:MainForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" }

                                $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                                $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                                $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                            }
                            $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                        }
                    }
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }
                $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
                if ($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }

                if ($null -ne $Script:RunTimeData.StopWatch) {
                    $Script:RunTimeData.StopWatch.Stop()
                    "Elapsed time: {0}" -f $Script:RunTimeData.StopWatch.Elapsed.ToString() | Write-LogOutput -LogType Debug
                    $Script:MainForm.Elements.TextBlockStatusBarQueryTime.Text = $Script:RunTimeData.StopWatch.Elapsed.ToString()
                }
            }
            catch {
                if ($null -ne $Private:TempQueryDoId) {
                    Remove-SqlQueryObject -DoId $Private:TempQueryDoId
                }
                $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
                if ($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }
                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        if ($null -ne $Script:RunTimeData.StopWatch) {
            $Script:RunTimeData.StopWatch.Stop()
            $Script:MainForm.Elements.TextBlockStatusBarQueryTime.Text = $Script:RunTimeData.StopWatch.Elapsed.ToString()
        }
        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
        if ($null -ne $Script:PopupWindowExecuteQuery) {
            $Script:PopupWindowExecuteQuery.Close()
        }

        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
