$Script:MainForm.Elements.ButtonShowOutput.Add_Click({
        try {
            $_ | Show-EventInfo
            "Show output" | Write-LogOutput
            $ColumnOrder = @($Script:MainForm.Elements.DataGridQueryResult.Columns | Sort-Object -Property DisplayIndex | ForEach-Object { "{0}" -f $_.Header })
            Show-QueryResultGridView -Rows $Script:RunTimeData.QueryResult.d.rows -Title ("{0} - {1}" -f $Form.Text, $Script:AppConfig.CurrentSqlQuery.FullName) -ColumnOrder $ColumnOrder
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
