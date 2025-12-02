function Set-EditorValue {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ($null -ne $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem) {
            "Selected SQL Query object: {0}" -f $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content | Write-LogOutput -LogType DEBUG
            $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content | Set-ConfigProperty -Property "CurrentSqlQuery"

            if ([string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected. Set correct values to execute queries!" | Write-LogOutput -LogType WARNING
                return
            }

            if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
                "Skip reconnect" | Write-LogOutput -LogType DEBUG
                return
            }

            if (!(Test-ConnectionRequirements)) {
                "Connection requirements are not met" | Write-LogOutput -LogType DEBUG
                return
            }

            $Private:Result = Get-SqlQueryObject
            if ($null -ne $Private:Result) {

                $Script:RunTimeData.CurrentSqlQuery.DoId = $Private:Result.Id
                $Script:RunTimeData.CurrentSqlQuery.DisplayName = $Private:Result.DisplayName

                $Script:MainWindowForm.Elements.TextBoxDisplayName.Text = $Private:Result.DisplayName
                $Private:Result.C_SQLTROUBLESHOOTING_DATACONNECTION.Id, $Private:Result.C_SQLTROUBLESHOOTING_DATACONNECTION.DisplayName | Set-ConfigProperty -Property "CurrentDataConnection"

                Set-DataConnection
                Set-SqlQueryFunctionState -Status $true
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainWindowForm.Elements.ButtonReset.IsEnabled = $true
                if ($null -ne $Script:Webview.Object.CoreWebView2) {

                    $ScriptToExecute = "editor.setValue('{0}');" -f ($Private:Result.C_QUERY -replace "`n", "\n" -replace "`r", "\r" -replace "`t", "\t" -replace "'", "\'")
                    Push-ToEditor -ScriptToExecute $ScriptToExecute
                    $Script:RunTimeData.CurrentQueryText = $Private:Result.C_QUERY
                    "Query {0} retrieved!" -f $Script:AppConfig.CurrentSqlQuery.DoId | Write-LogOutput
                }
            }
        }
        else {
            #Reset-Application -SkipTextBoxURL -SkipAuthentication
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
