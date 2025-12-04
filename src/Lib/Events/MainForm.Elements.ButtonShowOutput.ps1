$Script:MainForm.Elements.ButtonShowOutput.Add_Click({
        try {
            $_ | Show-EventInfo
            "Show output" | Write-LogOutput
            $Script:RunTimeData.QueryResult.d.rows | ConvertTo-Json -Depth 10 | Invoke-SanitizeJsonKeys | ConvertFrom-Json -Depth 10 | Out-GridView -Title ("{0} - {1}" -f $Form.Text, $Script:AppConfig.CurrentSqlQuery.FullName)
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#    $Script:MainForm.Elements.ButtonShowOutputText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonShowOutput"
#    }))

#$Script:MainForm.Elements.ButtonShowOutputImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonShowOutput"
#    }))
