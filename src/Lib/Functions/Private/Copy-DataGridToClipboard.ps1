function Copy-DataGridToClipboard {
    <#
    .SYNOPSIS
        Copies the DataGrid's currently selected cells to the clipboard.

    .DESCRIPTION
        Builds the clipboard text directly from DataGridQueryResult.SelectedCells instead of using the
        DataGrid's built-in copy command, because that command pads the output with empty placeholders for
        every column that is not part of the selection. Only the columns and rows that are actually part of
        the selection are included.

        Since issue #103 this function does cell extraction and Clipboard::SetText, and nothing else.
        Every decision about how a value becomes a literal lives in Format-QueryResultSelection and
        the two ConvertTo-*Literal functions, which have no UI dependency and are covered by tests.

        Two values are collected per cell, and the difference matters:

          * the RAW value from the row property, which still carries its CLR type. The array formats
            need it, because "{0}" -f a value is where the type is lost - a bit becomes 'False', a
            date is rendered under the thread culture, and a NULL becomes an empty string.
          * the RENDERED value from OnCopyingCellClipboardContent, which is what the user sees. The
            Default (tab separated) format is defined as "what the grid shows", so it keeps using
            this, and so does the pre-#103 sniffing path kept behind ArrayCopyUseColumnSchema.

    .PARAMETER IncludeHeader
        Prefix the clipboard content with a tab-separated header row containing the selected columns' headers.

    .PARAMETER OutputFormat
        "Default" produces tab-separated rows. "SqlArray" and "PowerShellArray" produce array literals
        typed from each column's own values - a single column as an array literal, several columns as
        a VALUES constructor or an array of PSCustomObject rows.

    .EXAMPLE
        Copy-DataGridToClipboard -IncludeHeader

    .EXAMPLE
        Copy-DataGridToClipboard -OutputFormat "SqlArray"

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

        $ColumnSchema = Get-DataGridSelectionSchema -DataGrid $DataGrid
        if ($null -eq $ColumnSchema -or $ColumnSchema.Count -eq 0) {
            return
        }

        $SelectedColumns = [System.Collections.Generic.List[object]]::new()
        $SelectedColumnSet = [System.Collections.Generic.HashSet[object]]::new()
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

        $CellValues = [System.Collections.Generic.List[string]]::new()
        $Lines = [System.Collections.Generic.List[string]]::new()
        $TypedRows = [System.Collections.Generic.List[object]]::new()

        if ($IncludeHeader) {
            $Lines.Add((($SelectedColumns | ForEach-Object { "{0}" -f $_.Header }) -join "`t"))
        }

        foreach ($Row in $SelectedRows) {
            $RowValues = [System.Collections.Generic.List[string]]::new()
            $TypedProperties = [ordered]@{}

            for ($ColumnIndex = 0; $ColumnIndex -lt $SelectedColumns.Count; $ColumnIndex++) {
                $Column = $SelectedColumns[$ColumnIndex]
                $PropertyName = $ColumnSchema[$ColumnIndex].PropertyName

                $CellInfo = [System.Windows.Controls.DataGridCellInfo]::new($Row, $Column)
                if ($DataGrid.SelectedCells.Contains($CellInfo)) {
                    $CellValue = "{0}" -f $Column.OnCopyingCellClipboardContent($Row)
                    $RowValues.Add($CellValue)
                    $CellValues.Add($CellValue)
                    $TypedProperties[$PropertyName] = $Row.$PropertyName
                }
                else {
                    # A cell the user did not select still needs a placeholder in a row-shaped
                    # literal, because a VALUES constructor cannot be ragged. This is the same
                    # choice Get-DataGridSelectedQueryResult documents for the same reason.
                    $TypedProperties[$PropertyName] = $null
                }
            }

            $Lines.Add(($RowValues -join "`t"))
            $TypedRows.Add([PSCustomObject]$TypedProperties)
        }

        $ClipboardText = $Lines -join "`r`n"
        if ([string]::IsNullOrWhiteSpace($ClipboardText)) {
            return
        }

        if ($OutputFormat -eq "Default") {
            [System.Windows.Clipboard]::SetText($ClipboardText)
            return
        }

        $Setting = Get-ArrayCopySetting

        if ($Setting.UseColumnSchema) {
            $FormattedText = Format-QueryResultSelection -Row @($TypedRows) -ColumnSchema $ColumnSchema -OutputFormat $OutputFormat -Setting $Setting
        }
        else {
            $FormattedText = Format-SniffedArrayLiteral -CellValue @($CellValues) -OutputFormat $OutputFormat
        }

        if ([string]::IsNullOrWhiteSpace($FormattedText)) {
            return
        }

        [System.Windows.Clipboard]::SetText($FormattedText)
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}

function Format-SniffedArrayLiteral {
    <#
    .SYNOPSIS
        The pre-#103 array formatting, kept verbatim behind ArrayCopyUseColumnSchema = $false.

    .DESCRIPTION
        Decides the literal type of the whole selection by sniffing the rendered text of every
        selected cell: all integers means unquoted, anything else means every value is quoted. That
        is the behaviour issue #103 replaces, and it is wrong in both directions - it turns the code
        "007" into 7, and one non-numeric cell in one column re-types the integers in every other
        column as strings.

        It is kept, unchanged and byte for byte, so a user who hits an unforeseen problem with the
        typed output has a switch back rather than a downgrade. Do not "fix" anything in here: its
        entire contract is that it still produces exactly what it produced before.

    .PARAMETER CellValue
        The rendered cell values, in selection order.

    .PARAMETER OutputFormat
        SqlArray or PowerShellArray.

    .OUTPUTS
        [string] the array literal.

    .NOTES
        No tracer preamble: called from the clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyCollection()]
        [string[]]$CellValue,
        [Parameter(Mandatory = $true)]
        [ValidateSet("SqlArray", "PowerShellArray")]
        [string]$OutputFormat
    )

    $AllValuesAreIntegers = ($CellValue | Where-Object { $_ -notmatch "^-?\d+$" }).Count -eq 0

    if ($OutputFormat -eq "SqlArray") {
        if ($AllValuesAreIntegers) {
            $FormattedText = $CellValue -join ",`r`n    "
        }
        else {
            $EscapedValues = $CellValue | ForEach-Object { ($_ -replace "'", "''") }
            $FormattedText = $EscapedValues -join "',`r`n    '"
            $FormattedText = "'{0}'" -f $FormattedText
        }

        return "(`r`n    {0}`r`n)" -f $FormattedText
    }

    if ($AllValuesAreIntegers) {
        $FormattedText = $CellValue -join ", "
        return "@({0})" -f $FormattedText
    }

    $EscapedValues = $CellValue | ForEach-Object { ($_ -replace "'", "''") }
    $FormattedText = $EscapedValues | ForEach-Object { "'{0}'" -f $_ }
    $FormattedText = $FormattedText -join ",`r`n    "

    return "@(`r`n    {0}`r`n)" -f $FormattedText
}
