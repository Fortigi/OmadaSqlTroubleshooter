function ConvertTo-QueryManagerTable {
    <#
    .SYNOPSIS
        Turns query objects into the table the query manager's grid shows.

    .DESCRIPTION
        A DataTable rather than the objects themselves: the grid sorts a typed column correctly - the
        Id column is numeric, so 10544 sorts after 9001 instead of before it. The columns are
        Get-QueryManagerColumnDefinition's, plus the query's technical Name, which the grid does not
        show: the name of a query without a display name is read from it (ConvertFrom-QueryManagerRow).

    .PARAMETER Query
        The query objects.

    .PARAMETER Ownership
        Who created and last changed each query (Get-QueryOwnership).

    .OUTPUTS
        [System.Data.DataTable]
    #>
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Query = @(),

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$Ownership = @{}
    )

    $Private:Table = [System.Data.DataTable]::new("Queries")
    foreach ($Private:Column in @(Get-QueryManagerColumnDefinition)) {
        $Private:Type = if ($Private:Column.Kind -eq "Id") { [long] } else { [string] }
        [void]$Private:Table.Columns.Add($Private:Column.Name, $Private:Type)
    }
    [void]$Private:Table.Columns.Add("Name", [string])

    foreach ($Private:Item in @($Query | Where-Object { $null -ne $_ })) {
        $Private:Values = ConvertTo-QueryManagerRow -Query $Private:Item -Ownership $Ownership
        $Private:Row = $Private:Table.NewRow()
        foreach ($Private:Name in $Private:Values.Keys) {
            $Private:Row[$Private:Name] = if ($null -eq $Private:Values[$Private:Name]) { [System.DBNull]::Value } else { $Private:Values[$Private:Name] }
        }
        $Private:Row["Name"] = [string]$Private:Item.Name
        $Private:Table.Rows.Add($Private:Row)
    }

    return , $Private:Table
}
