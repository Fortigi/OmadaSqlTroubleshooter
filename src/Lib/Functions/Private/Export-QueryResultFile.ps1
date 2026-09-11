function Export-QueryResultFile {
    <#
    .SYNOPSIS
        Writes a QueryResult-shaped object to a file, picking the format from the path's extension.

    .DESCRIPTION
        The pure, UI-free half of Save-QueryResultToFile: no dialog, no config, no form state, just
        "given this object and this path, write that file". Save-QueryResultToFile owns the
        SaveFileDialog and the LastOutputFolder/LastExtensionIndex bookkeeping and calls this for the
        actual write, which keeps the format dispatch - the part that has to escape delimiters, quotes,
        newlines and non-ASCII correctly - testable without a window.

        The extension decides the format, exactly as the dialog's filter list implies:
        .json  ConvertTo-Json -Depth 15, UTF8
        .csv   Export-Csv of the rows, ";" delimited, no type information, UTF8
        .xml   Export-Clixml of the whole object
        anything else  the rows as a plain text table

    .PARAMETER QueryResult
        A QueryResult-shaped object (PSCustomObject with a "d.rows" property) to write.

    .PARAMETER Path
        Full path of the file to write. Its extension selects the format.

    .EXAMPLE
        Export-QueryResultFile -QueryResult $Script:RunTimeData.QueryResult -Path "C:\temp\Output.csv"

    .NOTES
    #>

    [CmdLetBinding()]
    param (
        [parameter(Mandatory = $true)]
        [AllowNull()]
        [PSCustomObject]$QueryResult,
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    # The rows, for the two row-based formats below. A result with no rows at all - $null, or a
    # wrapper without the "d.rows" shape - becomes an empty set here, so CSV and plain text write
    # an empty export rather than failing. The Where-Object is doing real work and is not
    # defensive noise: @($null) is an array of one $null, not an empty array, and Export-Csv
    # refuses a null -InputObject, so without it "nothing to save" writes an error record.
    # JSON and CliXml do not use this - they serialize the whole wrapper as it was given, which
    # is the point of those two formats.
    $Row = @($QueryResult.d.rows | Where-Object { $null -ne $_ })

    if ($Path -like "*.json") {
        $QueryResult | ConvertTo-Json -Depth 15 | Set-Content $Path -Encoding UTF8
    }
    elseif ($Path -like "*.csv") {
        $Row | Export-Csv -Path $Path -Delimiter ";" -NoTypeInformation -Encoding UTF8
    }
    elseif ($Path -like "*.xml") {
        $QueryResult | Export-Clixml -Path $Path -Depth 15
    }
    else {
        ($Row | Format-Table -AutoSize | Out-String -Width 10000000).Trim() | Set-Content $Path -Encoding UTF8
    }
}
