$Script:MainWindowForm.Elements.TextBoxURL.Add_LostFocus({
    $_ | Show-EventInfo
    try {
        Set-OmadaUrl
        Test-ConnectionSettings
    }
    catch {
        $Script:MainWindowForm.Elements.ComboBoxSelectQuery.SelectedItem = $Null
        $Script:MainWindowForm.Elements.ButtonRefreshQueries.IsEnabled = $False
        if ($_.Exception.Response.StatusCode -eq "NotFound") {
            "SQL Troubleshooting Object not found or OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR
        }
        else {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }

    }
})
