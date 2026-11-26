# Cells as well as rows can be selected (Theme.DataGridStyle); SelectedCellsChanged fires for both.
# The buttons that act on one query follow the selection (Update-QueryManagerCommandState).
$Script:QueryManagerForm.Elements.DataGridQueries.Add_SelectedCellsChanged({
        try {
            Update-QueryManagerCommandState
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
