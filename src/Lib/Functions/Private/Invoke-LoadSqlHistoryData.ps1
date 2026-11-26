function Invoke-LoadSqlHistoryData {
    [CmdletBinding()]
    param()

    try {
        "Loading SQL history data..." | Write-LogOutput -LogType DEBUG

        # The query the window was opened for (Open-SqlHistoryForm -DoId), else the active tab's.
        $SqlHistoryObjects = if ($null -ne $Script:SqlHistoryTarget) { Get-SqlHistory -DoId $Script:SqlHistoryTarget.DoId } else { Get-SqlHistory }

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
        Update-DataGridColumnWidth -Grid $Private:HistoryGrid
        Select-SqlHistoryStartItem -Grid $Private:HistoryGrid -Item @($HistoryCollection)

        "Loaded {0} SQL history records" -f $HistoryCollection.Count | Write-LogOutput -LogType DEBUG
    }
    catch {
        # Contained. This is reached from a Loaded handler, and a terminating log here would unwind
        # into WPF's event dispatch rather than into anything that can act on it.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Select-SqlHistoryStartItem {
    <#
    .SYNOPSIS
        Selects, and scrolls to, the version the history window opens at: the one it was opened for
        (a double-clicked row of the query details' History tab, Find-SqlHistoryItemIndex), else the
        newest. A change that did not touch the SQL has no version: the newest, noted in the log.

    .PARAMETER Grid
        The version list.

    .PARAMETER Item
        Its versions, newest first.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Grid,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Item = @()
    )

    if ($Item.Count -eq 0) {
        return
    }

    $Private:Index = 0
    $Private:Target = $Script:SqlHistoryTarget
    if ($null -ne $Private:Target -and $null -ne $Private:Target.SelectChangeDate) {
        $Private:Index = Find-SqlHistoryItemIndex -Item $Item -ChangeDate $Private:Target.SelectChangeDate -ChangedBy $Private:Target.SelectChangedBy
        if ($Private:Index -lt 0) {
            "The change of {0} did not change the SQL, so it has no version here; showing the newest." -f $Private:Target.SelectChangeDate | Write-LogOutput -LogType DEBUG
            $Private:Index = 0
        }
    }

    $Grid.SelectedIndex = $Private:Index
    $Grid.ScrollIntoView($Item[$Private:Index])
}
