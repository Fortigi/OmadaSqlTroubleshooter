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

            # The schema window is optional: this function also feeds the editor's IntelliSense, which
            # must work whether or not the user ever opens the SQL schema view. Only touch the window's
            # title/TreeView when they actually exist (they are created by Open-SqlSchemaForm) - the
            # setSchema push below always runs.
            $UpdateSchemaWindow = ($null -ne $Script:SqlSchemaForm -and $null -ne $Script:SqlSchemaForm.Definition -and $null -ne $Script:TreeViewSqlSchema)

            if ($UpdateSchemaWindow) {
                $Script:SqlSchemaForm.Definition.Title = "Sql Schema - {0}" -f $Script:AppConfig.CurrentDataConnection.FullName
            }

            "Retrieved object {0}" -f $Script:RunTimeData.SqlQueryObject | Write-LogOutput -LogType VERBOSE

            $SchemaObjects = @{}
            if ($UpdateSchemaWindow) {
                $Script:TreeViewSqlSchema.Items.Clear()
            }

            $Schemas = (($ReturnValue.d | Get-Member -MemberType NoteProperty).Name) | ForEach-Object { $_.Split(".", 2)[0] } | Select-Object -Unique
            foreach ($Schema in $Schemas) {
                $Tables = $ReturnValue.d | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like ("{0}.*" -f $Schema) }

                $TreeViewSchemaItem = $null
                if ($UpdateSchemaWindow) {
                    $TreeViewSchemaItem = New-Object System.Windows.Controls.TreeViewItem
                    $TreeViewSchemaItem.Header = $Schema
                    $TreeViewSchemaItem.FontSize = 14
                    $TreeViewSchemaItem.IsExpanded = $true
                    $Script:TreeViewSqlSchema.Items.Add($TreeViewSchemaItem) | Out-Null
                }

                $TableObjects = @{}

                foreach ($Table in $Tables) {

                    $TableFullName = $Table.Name
                    $TableName = $TableFullName.Split(".", 2)[1]

                    $TreeViewTableItem = $null
                    if ($UpdateSchemaWindow) {
                        $TreeViewTableItem = New-Object System.Windows.Controls.TreeViewItem
                        $TreeViewTableItem.Header = $TableName
                        $TreeViewTableItem.FontSize = 14
                        $TreeViewSchemaItem.Items.Add($TreeViewTableItem) | Out-Null
                    }

                    # Each raw entry is "ColumnName DataType"; keep both so the editor can show the
                    # type in its completion detail. Split on the first run of whitespace (the type
                    # itself may contain spaces, e.g. "nvarchar(50) NOT NULL", so keep the remainder
                    # intact) and wrap in @() so a single-column table still serialises as a JSON
                    # array rather than a lone object.
                    $TableObjects.Add($TableName, @($ReturnValue.d.$TableFullName | ForEach-Object {
                                $Parts = $_.Trim() -split "\s+", 2
                                [PSCustomObject][Ordered]@{ n = $Parts[0]; t = if ($Parts.Count -gt 1) { $Parts[1].Trim() } else { "" } }
                            }))

                    if ($UpdateSchemaWindow) {
                        foreach ($Column in $ReturnValue.d.$TableFullName) {
                            $TreeViewColumnItem = New-Object System.Windows.Controls.TreeViewItem
                            $TreeViewColumnItem.Header = $Column
                            $TreeViewColumnItem.FontSize = 12
                            $TreeViewTableItem.Items.Add($TreeViewColumnItem) | Out-Null
                        }
                    }
                }
                $SchemaObjects.Add($Schema, $TableObjects)
            }

            if ($UpdateSchemaWindow) {
                # The tree was rebuilt from scratch above, so every node is visible again. Re-apply
                # whatever the user has typed in the filter box, otherwise switching tab or data
                # connection silently drops an active filter.
                Update-SqlSchemaTreeFilter
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
