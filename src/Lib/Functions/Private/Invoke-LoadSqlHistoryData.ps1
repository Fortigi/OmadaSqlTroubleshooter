function Invoke-LoadSqlHistoryData {
    [CmdletBinding()]
    param()

    try {
        "Loading SQL history data..." | Write-LogOutput -LogType DEBUG

        # Get SQL history using existing function
        $SqlHistoryObjects = Get-SqlHistory

        if ($null -eq $SqlHistoryObjects -or $SqlHistoryObjects.Count -eq 0) {
            "No SQL history data found" | Write-LogOutput -LogType WARNING
            return
        }

        # Create observable collection for data binding
        $HistoryCollection = New-Object System.Collections.ObjectModel.ObservableCollection[PSCustomObject]

        # Add items to collection (sorted by ChangeDate descending)
        $SortedHistory = $SqlHistoryObjects | Sort-Object ChangeDate -Descending
        foreach ($Item in $SortedHistory) {
            $HistoryCollection.Add($Item)
        }

        # Bind data to DataGrid
        $Script:SqlHistoryForm.Elements.DataGridHistory.ItemsSource = $HistoryCollection

        "Loaded {0} SQL history records" -f $HistoryCollection.Count | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
