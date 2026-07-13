$Script:MainForm.Elements.ComboBoxSelectQuery.Add_DropDownOpened({
        try {
            $_ | Show-EventInfo

            # Test-ConnectionRequirements only checks whether the URL/credential fields are filled
            # in, not whether the last connection attempt actually succeeded - those fields stay
            # populated after a failed authentication, so without this check, simply opening this
            # dropdown (something a user is likely to do repeatedly while troubleshooting a failed
            # connection) would keep calling Update-QueryList and re-hitting the server/re-triggering
            # authentication even though it is already known to have failed.
            if (-not $Script:ConnectionStatus) {
                "Not connected; skipping query list refresh." | Write-LogOutput -LogType DEBUG
                return
            }

            # if (($Script:MainForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -lt 1) {
            #     "Update query list" | Write-LogOutput -LogType DEBUG
            #     Update-QueryList
            #     #Update-DataConnectionList
            Update-QueryList

            # }
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq "NotFound") {
                "SQL Troubleshooting Object not found or OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
            else {
                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }

    })

$Script:MainForm.Elements.ComboBoxSelectQuery.Add_SelectionChanged({
        try {
            $_ | Show-EventInfo

            $Script:RunTimeData.CurrentSqlQuery.FullName = $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem.Content
            if (($Script:MainForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -ge 0 -and ![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem.Content)) {
                #Update-QueryList
                #Update-DataConnectionList
                if (Test-SqlHistoryFormOpen) {
                    $Script:SqlHistoryForm.Definition.Close()
                }
                Set-EditorValue
                Set-SqlQueryFunctionState -Status $true
                #Not working, needs to be investigated
                #Set-EditorBackground
            }

            # Selecting a query changes the tab's base name (rule 1 in Get-TabName).
            $ActiveTab = Get-ActiveTabSession
            if ($null -ne $ActiveTab) {
                Update-TabHeaderTitle -TabSession $ActiveTab
            }
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq "NotFound") {

                "SQL Troubleshooting Object not found for OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
            else {
                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }

    })
