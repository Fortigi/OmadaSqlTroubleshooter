function Format-ClipboardText {
    <#
    .SYNOPSIS
        Turns already-extracted cell values into the text that goes on the clipboard.

    .DESCRIPTION
        The pure, UI-free half of Copy-DataGridToClipboard: it takes plain strings rather than a
        DataGrid, so the escaping - which is the part that can silently corrupt a pasted query - is
        covered by tests/Format-ClipboardText.Tests.ps1 without a window or a clipboard.
        Copy-DataGridToClipboard keeps the selection walk and the single Clipboard::SetText call.

        "Default" produces tab-separated rows joined with CRLF, optionally preceded by a header row.
        "SqlArray" and "PowerShellArray" flatten every cell value (never the header) into one array
        literal, unquoted when every value is an integer and single-quoted - with any apostrophe
        doubled - otherwise.

        Returns nothing when the rows contain nothing but whitespace, so the caller leaves whatever
        is already on the clipboard alone.

    .PARAMETER Row
        The selected rows, each an array of that row's selected cell values in column order.

    .PARAMETER Header
        Optional header labels for the selected columns. Included in "Default" output only; the
        array formats deliberately ignore it, since a header is not a value.

    .PARAMETER OutputFormat
        "Default", "SqlArray" or "PowerShellArray".

    .EXAMPLE
        Format-ClipboardText -Row @(, @("1", "Alice")), @(, @("2", "Bob")) -Header @("Id", "Name")

    .EXAMPLE
        Format-ClipboardText -Row @(, @("1")), @(, @("2")) -OutputFormat SqlArray

    .NOTES
    #>

    [CmdLetBinding()]
    param (
        [parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[][]]$Row,
        [parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Header,
        [validateSet("SqlArray", "PowerShellArray", "Default")]
        [string]$OutputFormat = "Default"
    )

    $CellValues = [System.Collections.Generic.List[string]]::new()
    $Lines = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $Header -and $Header.Count -gt 0) {
        $Lines.Add(($Header -join "`t"))
    }

    foreach ($CurrentRow in $Row) {
        if ($null -eq $CurrentRow) {
            continue
        }

        foreach ($CellValue in $CurrentRow) {
            $CellValues.Add($CellValue)
        }
        $Lines.Add(($CurrentRow -join "`t"))
    }

    $ClipboardText = $Lines -join "`r`n"
    if ([string]::IsNullOrWhiteSpace($ClipboardText)) {
        return
    }

    # An "integer" here is only what matches ^-?\d+$: optional minus, then digits. A decimal, an
    # exponent, a leading plus, surrounding whitespace, a thousands separator or anything
    # non-numeric keeps its quotes, because pasting it unquoted would not mean the same value.
    # A leading zero does NOT keep its quotes - "007" matches, and pastes as the integer 7. That
    # is right for a numeric key and wrong for a zero-padded string key; it is long-standing
    # behaviour, pinned by a test in tests\Format-ClipboardText.Tests.ps1 rather than changed here.
    $AllValuesAreIntegers = ($CellValues | Where-Object { $_ -notmatch "^-?\d+$" }).Count -eq 0

    # An array literal is built from values, and the header is not one. With no values there is
    # nothing to paste, so say so rather than handing back an empty "(\r\n    \r\n)" - which a
    # header-only selection would otherwise produce, since the header alone makes $ClipboardText
    # non-empty above.
    if ($OutputFormat -ne "Default" -and $CellValues.Count -eq 0) {
        return
    }

    switch ($OutputFormat) {
        "SqlArray" {
            if ($AllValuesAreIntegers) {
                $FormattedText = $CellValues -join ",`r`n    "
            }
            else {
                $EscapedValues = $CellValues | ForEach-Object { ($_ -replace "'", "''") }
                $FormattedText = $EscapedValues -join "',`r`n    '"
                $FormattedText = "'{0}'" -f $FormattedText
            }
            $FormattedText = "(`r`n    {0}`r`n)" -f $FormattedText
        }
        "PowerShellArray" {
            if ($AllValuesAreIntegers) {
                $FormattedText = $CellValues -join ", "
                $FormattedText = "@({0})" -f $FormattedText
            }
            else {
                $EscapedValues = $CellValues | ForEach-Object { ($_ -replace "'", "''") }
                $FormattedText = $EscapedValues | ForEach-Object { "'{0}'" -f $_ }
                $FormattedText = $FormattedText -join ",`r`n    "
                $FormattedText = "@(`r`n    {0}`r`n)" -f $FormattedText
            }
        }
        default {
            $FormattedText = $ClipboardText
        }
    }

    return $FormattedText
}
