$Script:MainWindowForm.Elements.ButtonShowOutput.Add_Click({
    $_ | Show-EventInfo
    "Show output" | Write-LogOutput
    $Script:QueryResult.d.rows | Out-GridView -Title ("{0} - {1}" -f $Form.Text, $Script:AppConfig.SelectedSqlQueryDoId)
})
