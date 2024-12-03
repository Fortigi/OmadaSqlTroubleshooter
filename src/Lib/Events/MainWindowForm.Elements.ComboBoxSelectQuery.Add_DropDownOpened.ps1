$Script:MainWindowForm.Elements.ComboBoxSelectQuery.Add_DropDownOpened({
    $_ | Show-EventInfo
    try {
        if (($Script:MainWindowForm.Elements.ComboBoxSelectQuery.Items | Measure-Object).Count -le 1) {
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
