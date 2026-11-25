function Get-QueryManagerColumn {
    <#
    .SYNOPSIS
        The columns the query manager shows, in order, for the query objects OData returned.

    .DESCRIPTION
        Every field OData returns is shown - nothing is hard-coded beyond the order - so a tenant that
        exposes more about a query object shows more. Id, DisplayName and Name come first; the rest
        follow alphabetically. Left out: the OData annotations (@odata.*), the query text (C_QUERY,
        too long for a list; the detail view shows it) and Deleted (the list only holds queries that
        are not deleted).

    .PARAMETER Query
        The query objects.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Query = @()
    )

    $Private:Excluded = @("C_QUERY", "Deleted")
    $Private:First = @("Id", "DisplayName", "Name")

    $Private:Names = @($Query | Where-Object { $null -ne $_ } | ForEach-Object { $_.PSObject.Properties.Name } |
            Where-Object { $_ -notlike "@odata.*" -and $_ -notin $Private:Excluded } | Select-Object -Unique)

    $Private:Leading = @($Private:First | Where-Object { $_ -in $Private:Names })
    $Private:Rest = @($Private:Names | Where-Object { $_ -notin $Private:First } | Sort-Object)

    return [string[]]@($Private:Leading + $Private:Rest)
}
