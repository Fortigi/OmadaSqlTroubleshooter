function Format-QueryResultText {
    <#
    .SYNOPSIS
        Renders every statement's result as plain text, for the Results pane in text mode.

    .DESCRIPTION
        The "Results to Text" output of SQL Server Management Studio, with a header block per
        statement so each result set can be traced back to its query:

            Statement: 1
            Rows: 3 row(s)
            Query name: My saved query
            Query: --Test query 1 SELECT * FROM Test WHERE Id = 1

            Id          Name
            ----------- ------
            1           foo

            (3 row(s) affected)

        All statements go into one text, in editor order. A statement that ran and found nothing gets
        its header block and "(0 row(s) affected)" with no table, because there are no rows to read
        column names from. A failed statement is not passed in: its error is in the Messages pane.

        The table itself is Format-QueryResultTextTable. The work is spread over several small
        functions because the quality gate holds every unit to a complexity of 15.

    .PARAMETER StatementResult
        The tab's StatementResults, as Set-TabQueryResult stores them: Ordinal, DisplayText, Rows and
        RowCount per statement.

    .PARAMETER QueryName
        The display name of the saved query the run belongs to.

    .PARAMETER MaxColumnWidth
        The widest a column may be. Defaults to 256, the SSMS default.

    .OUTPUTS
        [string]

    .EXAMPLE
        Format-QueryResultText -StatementResult $TabSession.StatementResults -QueryName "My query"

    .NOTES
        No tracer preamble and no logging: the input is query results, which are identity data.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$StatementResult,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$QueryName,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxColumnWidth = 256
    )

    $NewLine = "`r`n"
    $Builder = [System.Text.StringBuilder]::new()

    foreach ($Statement in @($StatementResult | Where-Object { $null -ne $_ })) {
        $RowCount = [int]$Statement.RowCount

        [void]$Builder.Append(("Statement: {0}" -f $Statement.Ordinal)).Append($NewLine)
        [void]$Builder.Append(("Rows: {0:n0} row(s)" -f $RowCount)).Append($NewLine)
        [void]$Builder.Append(("Query name: {0}" -f $QueryName)).Append($NewLine)
        [void]$Builder.Append(("Query: {0}" -f (ConvertTo-SingleLineSqlText -Text ([string]$Statement.DisplayText) -NoCap))).Append($NewLine)
        [void]$Builder.Append($NewLine)
        [void]$Builder.Append((Format-QueryResultTextTable -Row @($Statement.Rows) -MaxColumnWidth $MaxColumnWidth))
        [void]$Builder.Append(("({0:n0} row(s) affected)" -f $RowCount)).Append($NewLine)
        [void]$Builder.Append($NewLine)
    }

    return $Builder.ToString()
}

function Format-QueryResultTextTable {
    <#
    .SYNOPSIS
        One result set as an SSMS-style text table, followed by a blank line.

    .DESCRIPTION
        Columns are separated by one space and underlined with dashes. A column is as wide as its
        longest value or its name, capped at MaxColumnWidth. A column whose values are all numbers is
        right-aligned, everything else left-aligned. The last column is not padded, so no line ends
        in spaces.

        SSMS sizes a column by its declared type. The Omada response carries values, not declared
        sizes, so the widths here come from the data.

        Returns an empty string when there are no rows or no columns.

    .PARAMETER Row
        The result rows.

    .PARAMETER MaxColumnWidth
        The widest a column may be.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Row,
        [int]$MaxColumnWidth = 256
    )

    $Column = @(Get-QueryResultTextColumn -Row $Row -MaxColumnWidth $MaxColumnWidth)
    if ($Column.Count -eq 0) {
        return ""
    }

    $NewLine = "`r`n"
    $Last = $Column.Count - 1
    $Builder = [System.Text.StringBuilder]::new()

    [void]$Builder.Append((@($Column | ForEach-Object { $_.Name.PadRight($_.Width) }) -join " ").TrimEnd()).Append($NewLine)
    [void]$Builder.Append((@($Column | ForEach-Object { [string]::new([char]"-", $_.Width) }) -join " ")).Append($NewLine)

    for ($RowIndex = 0; $RowIndex -lt $Column[0].Cell.Count; $RowIndex++) {
        $Line = for ($Index = 0; $Index -le $Last; $Index++) {
            Format-QueryResultTextCell -Column $Column[$Index] -RowIndex $RowIndex -IsLast:($Index -eq $Last)
        }

        [void]$Builder.Append(($Line -join " ")).Append($NewLine)
    }

    [void]$Builder.Append($NewLine)

    return $Builder.ToString()
}

function Format-QueryResultTextCell {
    <#
    .SYNOPSIS
        One cell of the text table, padded to its column.

    .PARAMETER Column
        The column, from Get-QueryResultTextColumn.

    .PARAMETER RowIndex
        The row.

    .PARAMETER IsLast
        The column is the last one: left-aligned text is not padded.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called once per cell.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        $Column,
        [int]$RowIndex,
        [switch]$IsLast
    )

    $Text = $Column.Cell[$RowIndex]

    if ($Column.IsNumeric) {
        return $Text.PadLeft($Column.Width)
    }

    if ($IsLast) {
        return $Text
    }

    return $Text.PadRight($Column.Width)
}

function Get-QueryResultTextColumn {
    <#
    .SYNOPSIS
        The columns of a result set, each with its formatted cells, width and alignment.

    .DESCRIPTION
        Columns come from the first row's property names, in order. Every cell is formatted once by
        ConvertTo-QueryResultTextValue, and the widths need every value before the first line can be
        written, so the whole table is formatted here before anything is laid out.

    .PARAMETER Row
        The result rows.

    .PARAMETER MaxColumnWidth
        The widest a column may be.

    .OUTPUTS
        [PSCustomObject] per column: Name, Cell (string[]), Width, IsNumeric.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Row,
        [int]$MaxColumnWidth = 256
    )

    $Rows = @($Row | Where-Object { $null -ne $_ })
    if ($Rows.Count -eq 0) {
        return
    }

    $ColumnName = @($Rows[0].PSObject.Properties | Where-Object { $_.MemberType -in @("NoteProperty", "Property") } | ForEach-Object { $_.Name })

    foreach ($Name in $ColumnName) {
        # foreach statements rather than pipelines: this runs once per cell, and the pipeline is what
        # makes a large result slow in PowerShell.
        $Value = [object[]]::new($Rows.Count)
        $Cell = [string[]]::new($Rows.Count)
        $Header = ConvertTo-QueryResultTextValue -Value $Name -MaxLength $MaxColumnWidth
        $Width = $Header.Length

        for ($Index = 0; $Index -lt $Rows.Count; $Index++) {
            $Value[$Index] = $Rows[$Index].$Name
            $Cell[$Index] = ConvertTo-QueryResultTextValue -Value $Value[$Index] -MaxLength $MaxColumnWidth
            $Width = [System.Math]::Max($Width, $Cell[$Index].Length)
        }

        [PSCustomObject]@{
            Name      = $Header
            Cell      = $Cell
            Width     = $Width
            IsNumeric = Test-QueryResultNumericColumn -Value $Value
        }
    }
}

function ConvertTo-QueryResultTextValue {
    <#
    .SYNOPSIS
        One value as the text output shows it.

    .DESCRIPTION
        NULL for a missing value, 1/0 for a boolean, yyyy-MM-dd HH:mm:ss.fff for a date, a number in
        invariant culture, and anything else as a string with its line breaks and tabs turned into
        spaces, so the table stays aligned. Cut off at MaxLength.

    .PARAMETER Value
        The raw value.

    .PARAMETER MaxLength
        The widest the text may be.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called once per cell.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        $Value,
        [int]$MaxLength = 256
    )

    if ($null -eq $Value) {
        return "NULL"
    }

    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $Code = [System.Type]::GetTypeCode($Value.GetType())

    $Text = if ($Code -eq [System.TypeCode]::DBNull) {
        "NULL"
    }
    elseif ($Code -eq [System.TypeCode]::Boolean) {
        if ($Value) { "1" } else { "0" }
    }
    elseif ($Code -eq [System.TypeCode]::DateTime) {
        $Value.ToString("yyyy-MM-dd HH:mm:ss.fff", $Invariant)
    }
    elseif (Test-QueryResultNumericTypeCode -Code $Code) {
        ([System.IFormattable]$Value).ToString($null, $Invariant)
    }
    else {
        ([string]$Value) -replace "\r\n|\r|\n|\t", " "
    }

    if ($Text.Length -gt $MaxLength) {
        return $Text.Substring(0, $MaxLength)
    }

    return $Text
}

function Test-QueryResultNumericTypeCode {
    <#
    .SYNOPSIS
        The type code is one of the numeric types, SByte through Decimal.

    .PARAMETER Code
        A [System.TypeCode].

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [System.TypeCode]$Code
    )

    return ($Code -ge [System.TypeCode]::SByte -and $Code -le [System.TypeCode]::Decimal)
}

function Test-QueryResultNumericColumn {
    <#
    .SYNOPSIS
        Every value in the column is a number, so the column is right-aligned.

    .DESCRIPTION
        NULLs are ignored. A column with nothing but NULLs has no numbers in it to align, and one
        string among the numbers makes the whole column text.

    .PARAMETER Value
        Every value of the column.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Value
    )

    $Present = @($Value | Where-Object { $null -ne $_ -and $_ -isnot [System.DBNull] })
    if ($Present.Count -eq 0) {
        return $false
    }

    $NonNumeric = @($Present | Where-Object { -not (Test-QueryResultNumericTypeCode -Code ([System.Type]::GetTypeCode($_.GetType()))) })

    return $NonNumeric.Count -eq 0
}
