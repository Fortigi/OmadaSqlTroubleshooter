function Select-QueryManagerQuery {
    <#
    .SYNOPSIS
        The query objects whose shown values match the query manager's filter.

    .DESCRIPTION
        A query matches when any of its shown columns contains the filter text, ignoring case, so a
        name, an id or a data connection all find it. * and ? are wildcards, exactly as in the schema
        view's filter (ConvertTo-WildcardFilterPattern). An empty filter keeps everything.

    .PARAMETER Query
        The query objects.

    .PARAMETER Filter
        The filter text.

    .OUTPUTS
        The matching query objects, in their original order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Query = @(),

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Filter
    )

    $Private:Pattern = ConvertTo-WildcardFilterPattern -FilterValue $Filter
    $Private:Columns = @(Get-QueryManagerColumn -Query $Query)

    foreach ($Private:Item in @($Query | Where-Object { $null -ne $_ })) {
        if ($null -eq $Private:Pattern) {
            $Private:Item
            continue
        }

        foreach ($Private:Name in $Private:Columns) {
            if ((ConvertTo-QueryManagerValue -Value $Private:Item.$Private:Name) -like $Private:Pattern) {
                $Private:Item
                break
            }
        }
    }
}
