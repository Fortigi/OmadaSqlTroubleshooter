function Get-SqlSchemaObject {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip reconnect" | Write-LogOutput -LogType DEBUG
            return
        }

        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
            "Retrieve current SqlSchema for data connection DoId: {0}" -f $Script:AppConfig.CurrentDataConnection.DoId | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/webservice/SyntaxHighlighting.asmx/GetSqlSchema" -f $Script:AppConfig.BaseUrl
            "SqlSchemaUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Retrieve schema {0}" -f $Script:AppConfig.CurrentDataConnection.FullName | Write-LogOutput

            # Share the schema across tabs that belong to the same connection pool (SessionKey) and
            # target the same data connection (DoId): same tenant + same database => identical
            # schema, so the first tab to fetch it populates a session-lifetime cache and every
            # other matching connected tab reuses it without another round-trip.
            $SchemaCacheKey = "{0}|{1}" -f $Script:RunTimeData.RestMethodParam.SessionKey, $Script:AppConfig.CurrentDataConnection.DoId
            if ($null -eq $Script:SqlSchemaCache) {
                $Script:SqlSchemaCache = @{}
            }

            if ($Script:SqlSchemaCache.ContainsKey($SchemaCacheKey)) {
                "Using cached SQL schema for '{0}'" -f $SchemaCacheKey | Write-LogOutput -LogType DEBUG
                $ReturnValue = $Script:SqlSchemaCache[$SchemaCacheKey]
            }
            else {
                $Script:RunTimeData.RestMethodParam.Body = @{
                    connectionId = $Script:AppConfig.CurrentDataConnection.DoId
                }
                $Script:RunTimeData.RestMethodParam.Method = "POST"
                $ReturnValue = Invoke-OmadaPSWebRequestWrapper

                if ($null -ne $ReturnValue -and $ReturnValue -isnot [System.Management.Automation.ErrorRecord] -and $null -ne $ReturnValue.d) {
                    $Script:SqlSchemaCache[$SchemaCacheKey] = $ReturnValue
                }
            }

            if ($null -eq $ReturnValue -or $ReturnValue -is [System.Management.Automation.ErrorRecord] -or $null -eq $ReturnValue.d) {
                "No SQL schema returned for data connection '{0}'." -f $Script:AppConfig.CurrentDataConnection.FullName | Write-LogOutput -LogType WARNING -SkipDialog
                return $null
            }

            $Script:SqlSchemaForm.Definition.Title = "Sql Schema - {0}" -f $Script:AppConfig.CurrentDataConnection.FullName

            "Retrieved object {0}" -f $Script:RunTimeData.SqlQueryObject | Write-LogOutput -LogType VERBOSE

            $SchemaObjects = @{}
            $Script:TreeViewSqlSchema.Items.Clear()
            $Schemas = (($ReturnValue.d | Get-Member -MemberType NoteProperty).Name) | ForEach-Object { $_.Split(".", 2)[0] } | Select-Object -Unique
            foreach ($Schema in $Schemas) {
                $Tables = $ReturnValue.d | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like ("{0}.*" -f $Schema) }

                $TreeViewSchemaItem = New-Object System.Windows.Controls.TreeViewItem
                $TreeViewSchemaItem.Header = $Schema
                $TreeViewSchemaItem.FontSize = 14
                $TreeViewSchemaItem.IsExpanded = $true
                $Script:TreeViewSqlSchema.Items.Add($TreeViewSchemaItem) | Out-Null

                #$SchemaObject = @{}
                $TableObjects = @{}

                foreach ($Table in $Tables) {

                    $TableFullName = $Table.Name
                    $TableName = $TableFullName.Split(".", 2)[1]

                    $TreeViewTableItem = New-Object System.Windows.Controls.TreeViewItem
                    $TreeViewTableItem.Header = $TableName
                    $TreeViewTableItem.FontSize = 14
                    $TreeViewSchemaItem.Items.Add($TreeViewTableItem) | Out-Null

                    # Each raw entry is "ColumnName DataType"; keep both so the editor can show the
                    # type in its completion detail. Split on the first space only, and wrap in @()
                    # so a single-column table still serialises as a JSON array (not a lone object).
                    $TableObjects.Add($TableName, @($ReturnValue.d.$TableFullName | ForEach-Object {
                                $Parts = $_.Split(" ", 2)
                                [PSCustomObject][Ordered]@{ n = $Parts[0]; t = if ($Parts.Count -gt 1) { $Parts[1] } else { "" } }
                            }))

                    #$SchemaObject.$Schema | Add-Member -Name $TableName -MemberType NoteProperty -Value $TableColumns

                    foreach ($Column in $ReturnValue.d.$TableFullName) {
                        $TreeViewColumnItem = New-Object System.Windows.Controls.TreeViewItem
                        $TreeViewColumnItem.Header = $Column
                        $TreeViewColumnItem.FontSize = 12
                        $TreeViewColumnItem.Font
                        $TreeViewTableItem.Items.Add($TreeViewColumnItem) | Out-Null
                    }
                }
                $SchemaObjects.Add($Schema, $TableObjects)
            }

            $SchemaObjectsJson = $SchemaObjects | ConvertTo-Json -Depth 5

            "Schema for Monaco editor: {0}" -f $SchemaObjectsJson | Write-LogOutput -LogType VERBOSE
            $OnCompletedScriptBlock = {
                try {
                    if (!$Script:Task.Status -eq "RanToCompletion") {
                        "Monaco Editor Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR -ErrorObject $_
                    }
                    else {
                        "Monaco Editor Task completed successfully." | Write-LogOutput -LogType DEBUG
                    }
                }
                catch {
                    $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

            "Push schema to Monaco editor." | Write-LogOutput -LogType DEBUG
            Invoke-ExecuteScriptAsync -ScriptToExecute "setSchema($SchemaObjectsJson);" -OnCompletedScriptBlock $OnCompletedScriptBlock

        }
        else {
            "SqlSchema DoID is not set! Cannot retrieve Sql schema!" | Write-LogOutput -LogType WARNING -SkipDialog
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
