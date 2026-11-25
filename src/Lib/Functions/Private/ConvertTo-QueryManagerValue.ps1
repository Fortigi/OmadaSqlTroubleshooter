function ConvertTo-QueryManagerValue {
    <#
    .SYNOPSIS
        Renders one OData field value as the text the query manager shows.

    .DESCRIPTION
        OData answers scalars, dates and references to other data objects. A reference (the data
        connection, for one) arrives as an object; it is shown by its display name with its id, the
        way the rest of the application names data objects ("OISES - 3"). Dates are shown in the same
        invariant form as the history window, so a column sorts and reads the same on every machine.

    .PARAMETER Value
        The field value.

    .OUTPUTS
        [string] Empty for $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [DateTime]) {
        return $Value.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [string] -or $Value.GetType().IsPrimitive) {
        return [string]$Value
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
        return (@($Value | ForEach-Object { ConvertTo-QueryManagerValue -Value $_ }) -join ", ")
    }

    $Private:Name = $Value.DisplayName
    $Private:Id = $Value.Id
    if (![string]::IsNullOrWhiteSpace($Private:Name)) {
        return $(if ($null -ne $Private:Id) { "{0} - {1}" -f $Private:Name, $Private:Id } else { [string]$Private:Name })
    }
    if ($null -ne $Private:Id) {
        return [string]$Private:Id
    }

    return ($Value | ConvertTo-Json -Compress -Depth 3)
}
