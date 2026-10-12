$Script:MainForm.Elements.ButtonShowOutput.Add_Click({
        try {
            $_ | Show-EventInfo
            "Show output" | Write-LogOutput
            # Both halves follow the focused result (issue #151). The columns come from the grid the
            # user is working in, and the rows from that same result - NOT from
            # $Script:RunTimeData.QueryResult, which holds only the first statement's response and
            # would silently show the top result whichever one the user had focused.
            $Private:FocusedGrid = Get-FocusedQueryResultGrid
            $Private:FocusedResult = Get-FocusedQueryResult
            $ColumnOrder = @($Private:FocusedGrid.Columns | Sort-Object -Property DisplayIndex | ForEach-Object { "{0}" -f $_.Header })
            Show-QueryResultGridView -Rows $Private:FocusedResult.QueryResult.d.rows -Title ("{0} - {1}" -f $Form.Text, $Script:AppConfig.CurrentSqlQuery.FullName) -ColumnOrder $ColumnOrder
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
