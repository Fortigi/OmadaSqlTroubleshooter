function Select-QueryManagerQuery {
    <#
    .SYNOPSIS
        The query objects that pass the query manager's filters: the text filter and the "Only my
        queries" filters.

    .DESCRIPTION
        Text: a query matches when any value its row shows (Get-QueryManagerColumnDefinition), or its
        technical name, contains the filter text, ignoring case - so a name, an id, a connection or a
        user finds it. * and ? are wildcards, as in the schema view's filter
        (ConvertTo-WildcardFilterPattern). An empty filter keeps everything. The query text is not
        searched.

        Only my queries: Test-QueryOwnedBy, with who created and last changed each query from
        -Ownership.

        View: Test-QueryManagerView - not deleted, deleted only, or all. The application's own
        temporary query objects (TMP_<guid>, which it deletes after every run) are never listed.

    .PARAMETER Query
        The query objects.

    .PARAMETER Filter
        The filter text.

    .PARAMETER Ownership
        Who created and last changed each query (Get-QueryOwnership).

    .PARAMETER UserName
        The signed-in user, as the view names users.

    .PARAMETER MyCreated
        Only queries the user created.

    .PARAMETER MyUpdated
        Only queries the user changed last.

    .PARAMETER View
        Active (not deleted, the default), Deleted or All.

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
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$Ownership = @{},

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$UserName,

        [bool]$MyCreated,

        [bool]$MyUpdated,

        [ValidateSet("Active", "Deleted", "All")]
        [string]$View = "Active"
    )

    if ($null -eq $Ownership) {
        $Ownership = @{}
    }
    $Private:Pattern = ConvertTo-WildcardFilterPattern -FilterValue $Filter

    foreach ($Private:Item in @($Query | Where-Object { $null -ne $_ -and (Test-QueryManagerView -Query $_ -View $View) })) {
        if (-not (Test-QueryOwnedBy -Owner $Ownership[[string]$Private:Item.Id] -UserName $UserName -Created $MyCreated -Updated $MyUpdated)) {
            continue
        }

        $Private:Values = @((ConvertTo-QueryManagerRow -Query $Private:Item -Ownership $Ownership).Values) + @($Private:Item.Name)
        if ($null -eq $Private:Pattern -or @($Private:Values | Where-Object { [string]$_ -like $Private:Pattern }).Count -gt 0) {
            $Private:Item
        }
    }
}

function Test-QueryManagerView {
    <#
    .SYNOPSIS
        Whether a query object belongs in the query manager's view: Active (not deleted), Deleted, or
        All. Never the application's own temporary query objects (NAME TMP_<guid>).

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        $Query,

        [ValidateSet("Active", "Deleted", "All")]
        [string]$View = "Active"
    )

    if ([string]$Query.Name -like "TMP_*") {
        return $false
    }

    $Private:Deleted = [string]$Query.Deleted -eq "True"
    switch ($View) {
        "Deleted" { return $Private:Deleted }
        "All" { return $true }
    }
    return -not $Private:Deleted
}
