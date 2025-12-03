$Script:MainFormForm.Elements.ButtonSaveQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            $Script:MainFormForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainFormForm.Elements.ButtonExecuteQuery.IsEnabled = $false

            if (!(Test-ConnectionRequirements) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
            }
            else {
                "Save query" | Write-LogOutput
                Invoke-SaveEditorValue
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })


