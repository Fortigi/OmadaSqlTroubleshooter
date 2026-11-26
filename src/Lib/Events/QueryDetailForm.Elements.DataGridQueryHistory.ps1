# Double-click a row of the History tab: the history window, at that version.
$Script:QueryDetailForm.Elements.DataGridQueryHistory.Add_MouseDoubleClick({
        try {
            $_ | Show-EventInfo
            Invoke-QueryDetailHistoryRow
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
