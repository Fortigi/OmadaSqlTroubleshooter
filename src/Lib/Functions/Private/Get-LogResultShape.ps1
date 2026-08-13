function Get-LogResultShape {
    <#
    .SYNOPSIS
        Describes a result set by its shape - row count, column count and column names - never its contents.

    .DESCRIPTION
        Query results returned by Omada are identity data. Logging them in full put PII into a log
        window that users can export and attach to a support ticket. This function replaces those
        dumps with the part that is actually diagnostic: how many rows came back and what the columns
        were called.

        NOTE: this function must never carry the standard $Script:Tracer preamble - the tracer routes
        through ConvertTo-RedactedLogString, and keeping the redaction helpers uninstrumented is what
        stops them calling themselves.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject,
        [int]$MaxColumnNames = 20
    )

    try {
        if ($null -eq $InputObject) {
            return "0 row(s)"
        }

        $Rows = @($InputObject) | Where-Object { $null -ne $_ }
        $RowCount = ($Rows | Measure-Object).Count
        if ($RowCount -le 0) {
            return "0 row(s)"
        }

        $FirstRow = $Rows[0]
        if ($FirstRow -is [System.Collections.IDictionary]) {
            $ColumnNames = @($FirstRow.Keys)
        }
        else {
            $ColumnNames = @($FirstRow.PSObject.Properties.Name)
        }

        $ColumnCount = ($ColumnNames | Measure-Object).Count
        if ($ColumnCount -le 0) {
            return "{0} row(s)" -f $RowCount
        }

        $ListedNames = $ColumnNames
        $Suffix = ""
        if ($ColumnCount -gt $MaxColumnNames) {
            $ListedNames = $ColumnNames | Select-Object -First $MaxColumnNames
            $Suffix = ", and {0} more" -f ($ColumnCount - $MaxColumnNames)
        }

        return "{0} row(s) x {1} column(s) [{2}{3}]" -f $RowCount, $ColumnCount, ($ListedNames -join ", "), $Suffix
    }
    catch {
        return "<result shape unavailable: {0}>" -f $_.Exception.Message
    }
}
