$Script:MainWindowForm.Elements.ButtonShowOutput.Add_Click({
        try {
            $_ | Show-EventInfo
            "Show output" | Write-LogOutput
            $Script:RunTimeData.QueryResult.d.rows | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10 | Out-GridView -Title ("{0} - {1}" -f $Form.Text, $Script:AppConfig.CurrentSqlQuery.FullName)
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    })
