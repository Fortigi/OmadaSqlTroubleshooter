$Script:MainWindowForm.Elements.TextBoxURL.Add_GotFocus({
    $_ | Show-EventInfo
    try {
        if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text) -and $Script:MainWindowForm.Elements.TextBlockUrl.Text -like "http*.omada.cloud" -and $Script:MainWindowForm.Elements.TextBlockUrl.Text -ne $Script:CurrentUrl) {
            $Script:CurrentUrl = $Script:MainWindowForm.Elements.TextBlockUrl.Text
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
})

$Script:MainWindowForm.Elements.TextBoxURL.Add_LostFocus({
    $_ | Show-EventInfo
    try {
        Set-OmadaUrl
        Test-ConnectionSettings
    }
    catch {

        if ($_.Exception.Response.StatusCode -eq "NotFound") {
            "SQL Troubleshooting Object not found or OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR
        }
        else {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
        Reset-Application -SkipTextBoxURL
    }
})

