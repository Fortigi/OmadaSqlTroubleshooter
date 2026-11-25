function ConvertTo-QueryManagerTable {
    <#
    .SYNOPSIS
        Turns query objects into the table the query manager's grid shows.

    .DESCRIPTION
        A DataTable rather than the objects themselves: the WPF DataGrid generates its columns from a
        DataView, and sorts a typed column correctly - the Id column is numeric, so 10544 sorts after
        9001 instead of before it. Every other value is shown as text (ConvertTo-QueryManagerValue).

    .PARAMETER Query
        The query objects.

    .OUTPUTS
        [System.Data.DataTable]
    #>
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Query = @()
    )

    $Private:Table = [System.Data.DataTable]::new("Queries")
    $Private:Columns = @(Get-QueryManagerColumn -Query $Query)

    foreach ($Private:Name in $Private:Columns) {
        $Private:Type = if ($Private:Name -eq "Id") { [long] } else { [string] }
        [void]$Private:Table.Columns.Add($Private:Name, $Private:Type)
    }

    foreach ($Private:Item in @($Query | Where-Object { $null -ne $_ })) {
        $Private:Row = $Private:Table.NewRow()
        foreach ($Private:Name in $Private:Columns) {
            $Private:Row[$Private:Name] = ConvertTo-QueryManagerCell -Name $Private:Name -Value $Private:Item.$Private:Name
        }
        $Private:Table.Rows.Add($Private:Row)
    }

    return , $Private:Table
}

function ConvertTo-QueryManagerCell {
    <#
    .SYNOPSIS
        The value one cell of the query manager's table holds: the id as a number, anything else as
        text, and a missing id as DBNull, which is how a DataTable stores "no value".

    .PARAMETER Name
        The column.

    .PARAMETER Value
        The field value.

    .OUTPUTS
        [long], [string] or [System.DBNull].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Value
    )

    if ($Name -ne "Id") {
        return ConvertTo-QueryManagerValue -Value $Value
    }

    if ($null -eq $Value) {
        return [System.DBNull]::Value
    }

    return [long]$Value
}
