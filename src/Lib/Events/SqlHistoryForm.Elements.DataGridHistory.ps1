# Cells as well as rows can be selected (Theme.DataGridStyle), so the panes follow SelectedCellsChanged,
# which fires for both; Update-SqlHistorySelection decides which version, if any, they show.
$Script:SqlHistoryForm.Elements.DataGridHistory.Add_SelectedCellsChanged({
        try {
            $_ | Show-EventInfo
            Update-SqlHistorySelection
        }
        catch {
            # Contained: this is a WPF selection handler, so a terminating log unwinds into the
            # event dispatch rather than into anything that can act on it.
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
