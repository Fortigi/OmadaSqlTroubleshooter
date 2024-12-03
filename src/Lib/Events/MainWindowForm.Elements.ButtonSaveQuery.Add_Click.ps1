$Script:MainWindowForm.Elements.ButtonSaveQuery.Add_Click({
    $_ | Show-EventInfo
    $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $False
    $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $False
    try {
        if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.SqlQueryDoId)) {
            "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
        }
        else {

            if ($InvokeOmadaRestMethodParam.ContainsKey("Credential") -and $Null -eq $InvokeOmadaRestMethodParam.Credential) {
                "Credential is not present, please check credential input!" | Write-LogOutput -LogType ERROR
            }

            "Save query" | Write-LogOutput

            Invoke-SaveQuery
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
})
