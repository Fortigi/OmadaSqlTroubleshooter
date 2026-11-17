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

        Formatting follows SSMS where the data allows it:

          * columns are separated by one space and underlined with dashes;
          * a column is as wide as its longest value or its name, capped at MaxColumnWidth (256 in
            SSMS); a longer value is cut off;
          * a column whose values are all numbers is right-aligned, everything else left-aligned;
          * NULL for a missing value, 1/0 for a boolean, yyyy-MM-dd HH:mm:ss.fff for a date;
          * a line break inside a value becomes a space, so the table stays aligned.

        SSMS sizes a column by its declared type. The Omada response carries values, not declared
        sizes, so the widths here come from the data.

        Values are formatted inline rather than through a helper function, because this runs once
        per cell and a function call per cell is what makes a large result slow in PowerShell.

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
    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $Builder = [System.Text.StringBuilder]::new()

    foreach ($Statement in @($StatementResult)) {
        if ($null -eq $Statement) {
            continue
        }

        $RowCount = [int]$Statement.RowCount
        $Rows = @($Statement.Rows | Where-Object { $null -ne $_ })

        [void]$Builder.Append(("Statement: {0}" -f $Statement.Ordinal)).Append($NewLine)
        [void]$Builder.Append(("Rows: {0:n0} row(s)" -f $RowCount)).Append($NewLine)
        [void]$Builder.Append(("Query name: {0}" -f $QueryName)).Append($NewLine)
        [void]$Builder.Append(("Query: {0}" -f (ConvertTo-SingleLineSqlText -Text ([string]$Statement.DisplayText) -NoCap))).Append($NewLine)
        [void]$Builder.Append($NewLine)

        if ($Rows.Count -gt 0) {
            $ColumnName = @($Rows[0].PSObject.Properties | Where-Object { $_.MemberType -in @("NoteProperty", "Property") } | ForEach-Object { $_.Name })
            $ColumnCount = $ColumnName.Count

            if ($ColumnCount -gt 0) {
                $Width = [int[]]::new($ColumnCount)
                $IsNumeric = [bool[]]::new($ColumnCount)
                $HasValue = [bool[]]::new($ColumnCount)

                for ($Index = 0; $Index -lt $ColumnCount; $Index++) {
                    $Width[$Index] = [System.Math]::Min($ColumnName[$Index].Length, $MaxColumnWidth)
                    $IsNumeric[$Index] = $true
                }

                # Every cell formatted once, then laid out. The widths need every value before the
                # first line can be written.
                $Cell = [System.Collections.Generic.List[string[]]]::new($Rows.Count)

                foreach ($Row in $Rows) {
                    $Line = [string[]]::new($ColumnCount)

                    for ($Index = 0; $Index -lt $ColumnCount; $Index++) {
                        $Value = $Row.($ColumnName[$Index])
                        if ($null -ne $Value -and $Value.GetType() -eq [System.Management.Automation.PSObject]) {
                            $Value = $Value.BaseObject
                        }

                        if ($null -eq $Value -or $Value -is [System.DBNull]) {
                            $Text = "NULL"
                        }
                        else {
                            $HasValue[$Index] = $true

                            if ($Value -is [bool]) {
                                $Text = if ($Value) { "1" } else { "0" }
                                $IsNumeric[$Index] = $false
                            }
                            elseif ($Value -is [datetime]) {
                                $Text = $Value.ToString("yyyy-MM-dd HH:mm:ss.fff", $Invariant)
                                $IsNumeric[$Index] = $false
                            }
                            elseif ($Value -is [System.DateTimeOffset]) {
                                $Text = $Value.ToString("yyyy-MM-dd HH:mm:ss.fffffff zzz", $Invariant)
                                $IsNumeric[$Index] = $false
                            }
                            elseif ($Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [double] -or $Value -is [single] -or $Value -is [short] -or $Value -is [byte] -or $Value -is [System.Numerics.BigInteger]) {
                                $Text = ([System.IFormattable]$Value).ToString($null, $Invariant)
                            }
                            else {
                                $Text = ([string]$Value) -replace "\r\n|\r|\n|\t", " "
                                $IsNumeric[$Index] = $false
                            }
                        }

                        if ($Text.Length -gt $MaxColumnWidth) {
                            $Text = $Text.Substring(0, $MaxColumnWidth)
                        }

                        if ($Text.Length -gt $Width[$Index]) {
                            $Width[$Index] = $Text.Length
                        }

                        $Line[$Index] = $Text
                    }

                    $Cell.Add($Line)
                }

                # A column with nothing but NULL has no numbers in it to align.
                for ($Index = 0; $Index -lt $ColumnCount; $Index++) {
                    if (-not $HasValue[$Index]) {
                        $IsNumeric[$Index] = $false
                    }
                }

                $Header = for ($Index = 0; $Index -lt $ColumnCount; $Index++) {
                    $Name = $ColumnName[$Index]
                    if ($Name.Length -gt $MaxColumnWidth) {
                        $Name = $Name.Substring(0, $MaxColumnWidth)
                    }

                    $Name.PadRight($Width[$Index])
                }

                $Dash = for ($Index = 0; $Index -lt $ColumnCount; $Index++) {
                    [string]::new([char]"-", $Width[$Index])
                }

                [void]$Builder.Append(((@($Header) -join " ").TrimEnd())).Append($NewLine)
                [void]$Builder.Append((@($Dash) -join " ")).Append($NewLine)

                foreach ($Line in $Cell) {
                    for ($Index = 0; $Index -lt $ColumnCount; $Index++) {
                        if ($Index -gt 0) {
                            [void]$Builder.Append(" ")
                        }

                        if ($IsNumeric[$Index]) {
                            [void]$Builder.Append($Line[$Index].PadLeft($Width[$Index]))
                        }
                        elseif ($Index -lt $ColumnCount - 1) {
                            [void]$Builder.Append($Line[$Index].PadRight($Width[$Index]))
                        }
                        else {
                            [void]$Builder.Append($Line[$Index])
                        }
                    }

                    [void]$Builder.Append($NewLine)
                }

                [void]$Builder.Append($NewLine)
            }
        }

        [void]$Builder.Append(("({0:n0} row(s) affected)" -f $RowCount)).Append($NewLine)
        [void]$Builder.Append($NewLine)
    }

    return $Builder.ToString()
}
