$Script:MainWindowForm.Elements.ComboBoxSelectQuery.Add_DropDownOpened({
    $_ | Show-EventInfo
    try {
        if (($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -lt 1) {
            "Update query list" | Write-LogOutput -LogType DEBUG
            Update-QueryList
            Update-DataConnectionList

        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "NotFound") {
            "SQL Troubleshooting Object not found or OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR
        }
        else {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    }

})

$Script:MainWindowForm.Elements.ComboBoxSelectQuery.Add_SelectionChanged({
    $_ | Show-EventInfo
    try {
        $Script:RunTimeData.CurrentSqlQuery.FullName = $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content
        if (($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -ge 0 -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem.Content)) {
            #Update-QueryList
            #Update-DataConnectionList
            Set-EditorValue
            #Not working, needs to be investigated
            #Set-EditorBackground
        }

    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "NotFound") {

            "SQL Troubleshooting Object not found for OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR
        }
        else {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    }

})
