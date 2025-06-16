$Script:MainWindowForm.Elements.ButtonRefreshQueries.Add_Click({
        try {
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
        }
        catch {
            [System.Windows.MessageBox]::Show("WebView2 initialization failed: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    })
