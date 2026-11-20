function Update-CachedQueryList {
    <#
    .SYNOPSIS
        Renames or removes one query in a tab's cached query list.

    .DESCRIPTION
        The cache (QueryListCache.QueryList) is an array of single-entry hashtables,
        @{ <DoId> = <DisplayName> }. Keys are compared as strings, because OData answers ids as
        numbers and the UI holds them as text. Every other entry is returned unchanged and in order.

    .PARAMETER QueryList
        The cached list. $null is an empty list.

    .PARAMETER DoId
        The query to change.

    .PARAMETER DisplayName
        Its new name (rename).

    .PARAMETER Remove
        Drop the entry instead of renaming it.

    .OUTPUTS
        The updated entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $QueryList,

        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [string]$DisplayName,

        [switch]$Remove
    )

    foreach ($Private:Entry in @($QueryList | Where-Object { $null -ne $_ })) {
        $Private:Keys = @()
        if ($Private:Entry -is [System.Collections.IDictionary]) {
            $Private:Keys = @($Private:Entry.Keys | ForEach-Object { [string]$_ })
        }

        if ($Private:Keys -notcontains $DoId) {
            $Private:Entry
            continue
        }

        if (-not $Remove) {
            # The original key, not its string form: Update-QueryList stores the id as OData answers it.
            $Private:Key = @($Private:Entry.Keys | Where-Object { [string]$_ -eq $DoId })[0]
            @{ $Private:Key = $DisplayName }
        }
    }
}
