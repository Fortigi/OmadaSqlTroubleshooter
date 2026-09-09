function Invoke-LoadSqlHistoryData {
    [CmdletBinding()]
    param()

    try {
        "Loading SQL history data..." | Write-LogOutput -LogType DEBUG

        $SqlHistoryObjects = Get-SqlHistory

        if ($null -eq $SqlHistoryObjects -or $SqlHistoryObjects.Count -eq 0) {
            "No SQL history data found" | Write-LogOutput -LogType WARNING
            return
        }

        $HistoryCollection = New-Object System.Collections.ObjectModel.ObservableCollection[PSCustomObject]

        # Add items to collection (sorted by ChangeDate descending)
        $SortedHistory = $SqlHistoryObjects | Sort-Object ChangeDate -Descending
        foreach ($Item in $SortedHistory) {
            $HistoryCollection.Add($Item)
        }

        # The window may be gone by now (issue #96). This runs from the history form's Loaded
        # handler, and Get-SqlHistory above BLOCKS for a full round-trip - so the window is on screen
        # and interactive throughout the fetch. Changing the selected query closes it
        # (MainFormTabContent.Elements.ComboBoxSelectQuery.ps1), and so does the user. The null guard
        # at the top of this function covers the DATA; nothing covered the FORM.
        # The whole chain, not just the leaf: a closed window can leave $Script:SqlHistoryForm itself
        # null, and under StrictMode walking into that is an error rather than a quiet $null.
        $Private:HistoryGrid = $null
        if ($null -ne $Script:SqlHistoryForm -and $null -ne $Script:SqlHistoryForm.Elements) {
            $Private:HistoryGrid = $Script:SqlHistoryForm.Elements.DataGridHistory
        }

        if ($null -eq $Private:HistoryGrid) {
            # Quietly: the user closed a window and has moved on. There is nothing to tell them and
            # nothing they could do about it.
            "The SQL history window closed while its data was loading; nothing to display into." | Write-LogOutput -LogType DEBUG
            return
        }

        $Private:HistoryGrid.ItemsSource = $HistoryCollection
        if ($HistoryCollection.Count -gt 0) {
            $Private:HistoryGrid.SelectedIndex = 0
        }

        "Loaded {0} SQL history records" -f $HistoryCollection.Count | Write-LogOutput -LogType DEBUG
    }
    catch {
        # Contained. This is reached from a Loaded handler, and a terminating log here would unwind
        # into WPF's event dispatch rather than into anything that can act on it.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
