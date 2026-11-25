function Get-CachedQueryName {
    <#
    .SYNOPSIS
        The display names in a tab's cached query list.

    .DESCRIPTION
        QueryListCache.QueryList is an array of single-entry hashtables, @{ <DoId> = <DisplayName> },
        built by Update-QueryList. This flattens it into the names, for checking a name the user typed
        against the queries the tab already knows (Test-SqlQueryName). Entries of any other shape are
        skipped.

    .PARAMETER QueryList
        The cached list. $null is an empty list.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $QueryList
    )

    foreach ($Private:Entry in @($QueryList)) {
        if ($Private:Entry -isnot [System.Collections.IDictionary]) {
            continue
        }
        foreach ($Private:Name in $Private:Entry.Values) {
            if (![string]::IsNullOrWhiteSpace($Private:Name)) {
                [string]$Private:Name
            }
        }
    }
}
