$Script:MainWindowForm.Elements.ButtonExecuteQuery.Add_Click({
        $_ | Show-EventInfo
        try {
            $Script:RunTimeData.StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

            $Script:PopupWindowExecuteQuery = Show-PopupWindow -Message "Executing Query..."

            $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonExecuteQuery | Set-ButtonContent -Content "Executing..."
            $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $False
            Start-Sleep -Milliseconds 100

            if (!(Test-ConnectionRequirements) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
            }
            else {
                "Execute query" | Write-LogOutput
                Invoke-SaveAndExecuteQuery
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })
