$Script:MainWindowForm.Elements.ButtonRefreshQueries.Add_Click({
    $_ | Show-EventInfo

    try {
        "Force update query list" | Write-LogOutput -LogType DEBUG
        Update-QueryList -ForceRefresh
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
