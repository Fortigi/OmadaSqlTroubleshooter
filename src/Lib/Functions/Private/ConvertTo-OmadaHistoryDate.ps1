function ConvertTo-OmadaHistoryDate {
    <#
    .SYNOPSIS
    Parse a change date from Omada's history grid, whatever culture rendered it.

    .DESCRIPTION
    Issue #95. The value comes from Omada's DataObjectHistory endpoint, which returns a jqGrid-style
    payload: "When" is a display string the SERVER formatted, not an ISO 8601 timestamp. So its
    format follows a locale, and not necessarily the one the client is running under.

    This used to be `Get-Date ($Row.When)`, which binds to a [DateTime] parameter and therefore
    converts using the CURRENT culture. On nl-NL the value "8/25/2026 12:03 PM" is read as day 8,
    month 25 - not a month - and the whole call failed:

        Cannot bind parameter 'Date'. Cannot convert value "8/25/2026 12:03 PM" to type
        "System.DateTime". Error: "String '8/25/2026 12:03 PM' was not recognized as a valid
        DateTime."

    Two cultures are tried, in order, and the order is the point. InvariantCulture first, because the
    observed value is month-first and matches it. CurrentCulture second, because a tenant that
    renders dates the local way would fail the other way round - "25-08-2026 12:03" is not a valid
    invariant date. Trying one and only one culture trades one locale's failure for another's.

    .NOTES
    The caller must not treat an unparsed date as fatal. Losing one row's timestamp is a cosmetic
    problem; losing the whole history list because one timestamp was unusual is the defect #95 was
    actually about - the failure propagated out of the row loop to the function's outer catch, and
    the user got an error dialog and no history at all.

    .PARAMETER Value
    The rendered date string from the history row.

    .OUTPUTS
    [DateTime] when it could be read, otherwise $null.
    #>
    [CmdLetBinding()]
    param(
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    # Already a DateTime - a future endpoint returning a real timestamp, or a test supplying one -
    # needs no parsing and must not be round-tripped through a culture.
    if ($Value -is [DateTime]) {
        return $Value
    }

    $Private:Text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($Private:Text)) {
        return $null
    }

    $Private:Parsed = [DateTime]::MinValue
    foreach ($Private:Culture in @([System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.CultureInfo]::CurrentCulture)) {
        if ([DateTime]::TryParse($Private:Text, $Private:Culture, [System.Globalization.DateTimeStyles]::None, [ref]$Private:Parsed)) {
            return $Private:Parsed
        }
    }

    # DEBUG, not an error. The row is still worth showing; only its date is unknown.
    "Could not read the history change date '{0}' under either the invariant or the current culture ({1})." -f $Private:Text, [System.Globalization.CultureInfo]::CurrentCulture.Name | Write-LogOutput -LogType DEBUG
    return $null
}
