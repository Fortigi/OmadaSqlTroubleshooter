$Script:MainWindowForm.Elements.ButtonExecuteQuery.Add_Click({
        try {
            $_ | Show-EventInfo

            $Script:RunTimeData.StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

            $Script:PopupWindowExecuteQuery = Show-PopupWindow -Message "Executing Query..."

            $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $false
            $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $false
            $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $false
            Start-Sleep -Milliseconds 100

            if (!(Test-ConnectionRequirements) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
                if ($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }
                Restore-MainWindowFocus
            }
            else {
                "Execute" | Write-LogOutput
                Invoke-ExecuteQuery
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
