$Script:MainWindowForm.Elements.ButtonExecuteQuery.Add_Click({
        $_ | Show-EventInfo
        try {
            $Script:StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

            $Script:PopupWindow = Show-PopupWindow -String "Executing Query..."

            $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonExecuteQuery.Content = "Executing..."
            $Script:MainWindowForm.Elements.ButtonShowOutput.IsEnabled = $False
            $Script:MainWindowForm.Elements.ButtonSaveOutputFile.IsEnabled = $False
            Start-Sleep -Milliseconds 100

            if ([string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.SqlQueryDoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
            }
            else {

                if ($InvokeOmadaRestMethodParam.ContainsKey("Credential") -and $Null -eq $InvokeOmadaRestMethodParam.Credential) {
                    "Credential is not present, please check credential input!" | Write-LogOutput -LogType ERROR
                }

                "Execute query" | Write-LogOutput

                Invoke-SaveAndExecuteQuery
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })
