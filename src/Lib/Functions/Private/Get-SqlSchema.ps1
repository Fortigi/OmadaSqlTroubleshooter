function Get-SqlSchemaObject {
    try {

        if(!(Test-ConnectionRequirements)){
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.DoId)) {
            "Retrieve current SqlSchema for data connection DoId: {0}" -f $Script:AppConfig.CurrentDataConnection.DoId | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/webservice/SyntaxHighlighting.asmx/GetSqlSchema" -f $Script:AppConfig.BaseUrl
            "SqlSchemaUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Retrieve schema {0}" -f $Script:AppConfig.CurrentDataConnection.FullName | Write-LogOutput

            $Script:RunTimeData.RestMethodParam.Body = @{
                connectionId = $Script:AppConfig.CurrentDataConnection.DoId
            }
            $Script:RunTimeData.RestMethodParam.Method = "POST"
            $ReturnValue = Invoke-OmadaPSWebRequestWrapper

            $Script:SqlSchemaWindowForm.Definition.Title = "Sql Schema - {0}" -f $Script:AppConfig.CurrentDataConnection.FullName

            "Retrieved object {0}" -f $Script:RunTimeData.SqlQueryObject | Write-LogOutput -LogType VERBOSE

            $SchemaObjects = @{}
            $Script:TreeViewSqlSchema.Items.Clear()
            $Schemas = (($ReturnValue.d | Get-Member -MemberType NoteProperty).Name) | ForEach-Object { $_.Split(".")[0] } | Select-Object -Unique
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
                    $TableName = $TableFullName.Split(".")[1]

                    $TreeViewTableItem = New-Object System.Windows.Controls.TreeViewItem
                    $TreeViewTableItem.Header = $TableName
                    $TreeViewTableItem.FontSize = 14
                    $TreeViewSchemaItem.Items.Add($TreeViewTableItem) | Out-Null

                    $TableObjects.Add($TableName,($ReturnValue.d.$TableFullName | ForEach-Object { $_.Split(" ")[0] }))

                    #$SchemaObject.$Schema | Add-Member -Name $TableName -MemberType NoteProperty -Value $TableColumns

                    foreach ($Column in $ReturnValue.d.$TableFullName) {
                        $TreeViewColumnItem = New-Object System.Windows.Controls.TreeViewItem
                        $TreeViewColumnItem.Header = $Column
                        $TreeViewColumnItem.FontSize = 12
                        $TreeViewColumnItem.Font
                        $TreeViewTableItem.Items.Add($TreeViewColumnItem) | Out-Null
                    }
                }
                $SchemaObjects.Add($Schema,$TableObjects)
            }

            $SchemaObjectsJson = $SchemaObjects | ConvertTo-Json -Depth 5

            "Schema for Monaco editor: {0}" -f $SchemaObjectsJson | Write-LogOutput -LogType VERBOSE
            $OnCompletedScriptBlock = {
                try {
                    if (!$Script:Task.Status -eq "RanToCompletion") {
                        "Monaco Editor Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                    }
                    else{
                        "Monaco Editor Task completed successfully." | Write-LogOutput -LogType DEBUG
                    }
                }
                catch {
                    $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR
                }
            }

            "Push schema to Monaco editor." | Write-LogOutput -LogType DEBUG
            Invoke-ExecuteScriptAsync -ScriptToExecute "setSchema($SchemaObjectsJson);" -OnCompletedScriptBlock $OnCompletedScriptBlock

        }
        else {
            "SqlSchema DoID is not set! Cannot retrieve Sql schema!" | Write-LogOutput -LogType WARNING
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
