function Copy-DataGridToClipboard {
    <#
    .SYNOPSIS
        Copies the DataGrid's currently selected cells to the clipboard.

    .DESCRIPTION
        Builds the clipboard text directly from DataGridQueryResult.SelectedCells instead of using the
        DataGrid's built-in copy command, because that command pads the output with empty placeholders for
        every column that is not part of the selection. Only the columns and rows that are actually part of
        the selection are included.

    .PARAMETER IncludeHeader
        Prefix the clipboard content with a tab-separated header row containing the selected columns' headers.

    .PARAMETER OutputFormat
        "Default" produces tab-separated rows. "SqlArray" and "PowerShellArray" flatten every selected cell
        value into a single array literal, formatted as unquoted integers when every selected value is one.

    .EXAMPLE
        Copy-DataGridToClipboard -IncludeHeader

    .NOTES
    #>

    [CmdLetBinding()]
    param (
        [switch]$IncludeHeader,
        [validateSet("SqlArray", "PowerShellArray", "Default")]
        [string]$OutputFormat = "Default"
    )

    try {
        $DataGrid = $Script:MainForm.Elements.DataGridQueryResult

        if ($DataGrid.SelectedCells.Count -le 0) {
            return
        }

        $SelectedColumnSet = [System.Collections.Generic.HashSet[object]]::new()
        $SelectedColumns = [System.Collections.Generic.List[object]]::new()
        foreach ($SelectedCell in $DataGrid.SelectedCells) {
            if ($SelectedColumnSet.Add($SelectedCell.Column)) {
                $SelectedColumns.Add($SelectedCell.Column)
            }
        }
        $SelectedColumns = @($SelectedColumns | Sort-Object -Property DisplayIndex)

        $SelectedRowSet = [System.Collections.Generic.HashSet[object]]::new()
        foreach ($SelectedCell in $DataGrid.SelectedCells) {
            $SelectedRowSet.Add($SelectedCell.Item) | Out-Null
        }
        $SelectedRows = @($DataGrid.Items | Where-Object { $SelectedRowSet.Contains($_) })

        $Header = $null
        if ($IncludeHeader) {
            $Header = @($SelectedColumns | ForEach-Object { "{0}" -f $_.Header })
        }

        $Rows = [System.Collections.Generic.List[string[]]]::new()
        foreach ($Row in $SelectedRows) {
            $RowValues = [System.Collections.Generic.List[string]]::new()
            foreach ($Column in $SelectedColumns) {
                $CellInfo = [System.Windows.Controls.DataGridCellInfo]::new($Row, $Column)
                if ($DataGrid.SelectedCells.Contains($CellInfo)) {
                    $RowValues.Add(("{0}" -f $Column.OnCopyingCellClipboardContent($Row)))
                }
            }
            $Rows.Add($RowValues.ToArray())
        }

        # Everything from here on is string work with no WPF in it, so it lives in
        # Format-ClipboardText and is covered by tests/Format-ClipboardText.Tests.ps1.
        $FormattedText = Format-ClipboardText -Row $Rows.ToArray() -Header $Header -OutputFormat $OutputFormat
        if ([string]::IsNullOrWhiteSpace($FormattedText)) {
            return
        }

        [System.Windows.Clipboard]::SetText($FormattedText)
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
