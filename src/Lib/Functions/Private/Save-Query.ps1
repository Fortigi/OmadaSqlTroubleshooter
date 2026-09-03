function Save-Query {
    [CmdLetBinding()]
    param(
        [switch]$NewQuery
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if ($NewQuery) {
            "Create new query" | Write-LogOutput -LogType DEBUG

            $Script:RunTimeData.RestMethodParam.Uri = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$filter=Deleted ne true and NAME eq ''{1}''' -f $Script:AppConfig.BaseUrl, $Script:MainForm.Elements.TextBoxDisplayName.Text
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG
            "Check if a query with this name already exists" | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Body = $null
            $Script:RunTimeData.RestMethodParam.Method = "GET"
            $Script:RunTimeData.RestMethodParam.Body = $null
            $CheckIfExistResult = Invoke-OmadaPSWebRequestWrapper
            if ($null -eq $CheckIfExistResult -or ($CheckIfExistResult.Value | Measure-Object).Count -le 0) {
                $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Script:AppConfig.BaseUrl
                $Script:RunTimeData.RestMethodParam.Method = "POST"
            }
            else {

                $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true

                "Query with this name already exists!" | Write-LogOutput -LogType ERROR
                return
            }
        }
        else {
            "Save existing query" | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING({1})" -f $Script:AppConfig.BaseUrl, $Script:AppConfig.CurrentSqlQuery.DoId
            $private:Result = Get-SqlQueryObject
            $Script:RunTimeData.RestMethodParam.Method = "PUT"
        }

        # The diff rules and the URL come from New-OmadaQueryRequest, which is also what the
        # background pipeline uses inside the worker (issue #40, C1-5). One definition of "what does
        # saving a query send, and when is there nothing to send" - two copies of that would drift,
        # and the drift would only show up against a real tenant.
        $Private:SaveContext = @{
            BaseUrl            = $Script:AppConfig.BaseUrl
            QueryDoId          = $Script:AppConfig.CurrentSqlQuery.DoId
            QueryText          = $Script:RunTimeData.QueryText
            CurrentQueryText   = $Script:RunTimeData.CurrentQueryText
            SavedQueryText     = $private:Result.C_QUERY
            DisplayName        = $Script:MainForm.Elements.TextBoxDisplayName.Text
            CurrentDisplayName = $Script:RunTimeData.CurrentSqlQuery.DisplayName
            DataConnectionDoId = $Script:AppConfig.CurrentDataConnection.DoId
        }
        $Private:SaveRequest = New-OmadaQueryRequest -Kind "SaveExistingQuery" -Context $Private:SaveContext

        # A new query always has a body: there is nothing on the server to compare against, so the
        # "nothing changed" answer cannot apply. The URI and method for that case were set above.
        $Script:RunTimeData.RestMethodParam.Body = if ($null -ne $Private:SaveRequest) { $Private:SaveRequest.Body } else { @{} }
        if ($NewQuery) {
            $Script:RunTimeData.RestMethodParam.Body = @{ "C_QUERY" = $Script:RunTimeData.QueryText }
            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
                $Script:RunTimeData.RestMethodParam.Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{Id = $Script:AppConfig.CurrentDataConnection.DoId })
            }
            if ($Script:RunTimeData.CurrentSqlQuery.DisplayName -ne $Script:MainForm.Elements.TextBoxDisplayName.Text) {
                $Script:RunTimeData.RestMethodParam.Body.Add("NAME", $Script:MainForm.Elements.TextBoxDisplayName.Text)
            }
        }

        if (!$NewQuery -and $null -eq $Private:SaveRequest) {
            "No changes detected! Saving not needed." | Write-LogOutput -LogType DEBUG
            return $private:Result
        }
        else {

            "Saving SQL Query: {0}" -f $Script:RunTimeData.QueryText | Write-LogOutput -LogType DEBUG
            "Body: {0}" -f (ConvertTo-RedactedLogString -InputObject $Script:RunTimeData.RestMethodParam.Body -ShapeOnly) | Write-LogOutput -LogType VERBOSE
            "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Save query" | Write-LogOutput
            $private:Result = Invoke-OmadaPSWebRequestWrapper

            if ($null -ne $private:Result -and $NewQuery -or $private:Result.DisplayName -ne $Script:RunTimeData.CurrentSqlQuery.DisplayName) {
                "Query saved!" | Write-LogOutput
                if ($NewQuery) {
                    $Script:RunTimeData.CurrentSqlQuery.DoId = $private:Result.Id
                    $Script:RunTimeData.CurrentSqlQuery.DisplayName = $private:Result.Name
                    $private:Result.Id, $private:Result.Name | Set-ConfigProperty -Property "CurrentSqlQuery"
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                    $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null

                    # Make the new query show up in every other connected tab that shares this
                    # connection pool (and refresh this tab's own query cache with it).
                    Add-QueryToConnectedPoolTabs -DoId $private:Result.Id -DisplayName $private:Result.Name -FullName $Script:AppConfig.CurrentSqlQuery.FullName
                }
                else {
                    "New display name, Current: {0}, New: {1}" -f $Script:RunTimeData.CurrentSqlQuery.DisplayName, $private:Result.DisplayName | Write-LogOutput -LogType VERBOSE
                    "Force update query list" | Write-LogOutput -LogType DEBUG
                    Update-QueryList -ForceRefresh
                    $Script:RunTimeData.CurrentSqlQuery.DoId = $Script:AppConfig.CurrentSqlQuery.DoId
                    $ComboBoxSelectQueryItem = $Script:MainForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" }
                    if ($null -eq $ComboBoxSelectQueryItem) {
                        $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                        $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                        $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                    }
                }
                $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
                $Script:RunTimeData.CurrentSqlQuery.DisplayName = $private:Result.DisplayName
                return $private:Result
            }
            else {
                return $private:Result
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
