# Query manager window events (see Open-QueryManagerForm).

$Script:QueryManagerForm.Elements.TextBoxQueryFilter.Add_TextChanged({
        try {
            # Filters the list already read; no request.
            Update-QueryManagerList
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryManagerForm.Elements.ButtonRefreshQueryList.Add_Click({
        try {
            $_ | Show-EventInfo
            Update-QueryManagerList -Refresh
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryManagerForm.Elements.DataGridQueries.Add_MouseDoubleClick({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "Details"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryManagerForm.Elements.ButtonCloseQueryManager.Add_Click({
        $Script:QueryManagerForm.Definition.Close()
    })

# The "Only my queries" filters work on the list already read (and the view read with it); no request.
foreach ($Private:FilterBox in @($Script:QueryManagerForm.Elements.CheckBoxQueryManagerMyCreated, $Script:QueryManagerForm.Elements.CheckBoxQueryManagerMyUpdated)) {
    $Private:FilterBox.Add_Click({
            try {
                Update-QueryManagerList
            }
            catch {
                $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
            }
        })
}
