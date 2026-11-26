function Get-QueryHistorySummary {
    <#
    .SYNOPSIS
        When and by whom a query object was created and last changed, from its change history.

    .DESCRIPTION
        OData does not return these for a C_P_SQLTROUBLESHOOTING object, but the object's history
        does: its Create entry, and its most recent entry of any kind. Unknown when the history has
        no such entry (a history that was purged, or a create that predates it).

    .PARAMETER Entry
        The entries from ConvertTo-QueryHistoryEntry.

    .OUTPUTS
        [PSCustomObject] @{ Created; CreatedBy; Changed; ChangedBy }, each $null when unknown.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Entry = @()
    )

    $Private:Dated = @($Entry | Where-Object { $null -ne $_ -and $null -ne $_.When } | Sort-Object -Property When)
    # "Create", but also "Created" or "Creation": the action text is the tenant's, not ours.
    $Private:Create = @($Private:Dated | Where-Object { $_.What -match '^\s*Creat' }) | Select-Object -First 1
    $Private:Latest = $Private:Dated | Select-Object -Last 1

    return [PSCustomObject]@{
        Created   = $Private:Create.When
        CreatedBy = $Private:Create.Who
        Changed   = $Private:Latest.When
        ChangedBy = $Private:Latest.Who
    }
}
