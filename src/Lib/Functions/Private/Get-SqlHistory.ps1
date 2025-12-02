function Get-SqlHistory {
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
            "Retrieve current SqlHistory for data connection DoId: {0}" -f $Script:AppConfig.CurrentDataConnection.DoId | Write-LogOutput -LogType DEBUG
            $Script:RunTimeData.RestMethodParam.Uri = "{0}/WebService/JQGridPopulationWebService.asmx/GetPagingData" -f $Script:AppConfig.BaseUrl
            "SqlHistoryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

            "Retrieve history {0}" -f $Script:AppConfig.CurrentDataConnection.FullName | Write-LogOutput

            $Script:RunTimeData.RestMethodParam.Uri = "{0}/webservice/jQGridPopulationWebService.asmx/GetPagingData" -f $Script:AppConfig.BaseUrl

            $Script:RunTimeData.RestMethodParam.Body = @{
                "dataType"     = "DataObjectHistory"
                "dataTypeArgs" = @{
                    "dataObjectId" = $Script:AppConfig.CurrentSqlQuery.DoId
                    "propertyId"   = 0
                    "userId"       = 0
                }
                "page"         = 1
                "rows"         = 100000
                "sidx"         = "when"
                "sord"         = "desc"
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
            $Script:RunTimeData.HistoryResult = $null
            $Script:RunTimeData.HistoryResult = Invoke-OmadaPSWebRequestWrapper

            "Retrieved object {0}" -f $Script:RunTimeData.SqlQueryObject | Write-LogOutput -LogType VERBOSE

            $SqlHistoryObjects = @()
            foreach ($Row in $Script:RunTimeData.HistoryResult.d.Rows) {

                $ChangedFields = $Row.ChangedFields | ConvertFrom-Json
                foreach ($ChangedField in $ChangedFields) {

                    if ($ChangedField.Field -ne "SQL Query") {
                        continue
                    }

                    if ($ChangedField.OldValue -eq $null -or $ChangedField.OldValue -eq '[N/A]') {
                        $ChangedField.OldValue = $null
                    }

                    $SqlHistoryObject = [PSCustomObject]@{
                        DoId          = $Script:AppConfig.CurrentSqlQuery.DoId
                        SqlObjectName = $Row.Object
                        OldValue      = $ChangedField.OldValue
                        NewValue      = $ChangedField.NewValue
                        ChangedBy     = $Row.Who
                        ChangeType    = $Row.What
                        ChangeDate    = (Get-Date ($Row.When))
                    }
                    $SqlHistoryObjects += $SqlHistoryObject

                }
            }
            return $SqlHistoryObjects
        }
        else {
            "SqlHistory DoID is not set! Cannot retrieve Sql history!" | Write-LogOutput -LogType WARNING -SkipDialog
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
