function ConvertTo-QueryPropertyList {
    <#
    .SYNOPSIS
        The name / value pairs the query details' Properties tab shows for one query object.

    .DESCRIPTION
        The query manager's columns (Get-QueryManagerColumnDefinition), in the same order, under the
        same names and shown the same way, so the list and the details agree.

        Created and Changed come from OData (CreateTime, ChangeTime), Created by and Changed by from
        the tenant's SQL Troubleshooting view (-Ownership). When one of those four is empty - a tenant
        without the view, an object that could not be read - the object's history fills it in
        (Get-QueryHistorySummary), so a value is shown whenever any source has it.

    .PARAMETER Query
        The query object, as returned by GET C_P_SQLTROUBLESHOOTING(<id>).

    .PARAMETER Ownership
        Who created and last changed each query (Get-QueryOwnership).

    .PARAMETER HistoryEntry
        Its history, from ConvertTo-QueryHistoryEntry.

    .OUTPUTS
        [PSCustomObject] @{ Property; Value }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Query,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$Ownership = @{},

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$HistoryEntry = @()
    )

    $Private:Values = if ($null -ne $Query) { ConvertTo-QueryManagerRow -Query $Query -Ownership $Ownership } else { @{} }
    $Private:Summary = Get-QueryHistorySummary -Entry $HistoryEntry
    $Private:Fallback = @{
        CreateTime = ConvertTo-QueryManagerValue -Value $Private:Summary.Created
        CreatedBy  = [string]$Private:Summary.CreatedBy
        ChangeTime = ConvertTo-QueryManagerValue -Value $Private:Summary.Changed
        ChangedBy  = [string]$Private:Summary.ChangedBy
    }

    foreach ($Private:Column in @(Get-QueryManagerColumnDefinition)) {
        $Private:Value = [string]$Private:Values[$Private:Column.Name]
        if ([string]::IsNullOrWhiteSpace($Private:Value) -and $Private:Fallback.ContainsKey($Private:Column.Name)) {
            $Private:Value = $Private:Fallback[$Private:Column.Name]
        }
        [PSCustomObject]@{ Property = $Private:Column.Header; Value = $Private:Value }
    }
}
