$Script:MainWindowForm.Elements.ButtonSaveQuery.Add_Click({
        $_ | Show-EventInfo
        $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $False
        $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $False
        try {
            if (!(Test-ConnectionRequirements) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
            }
            else {
                "Save query" | Write-LogOutput
                Invoke-SaveQuery
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })


