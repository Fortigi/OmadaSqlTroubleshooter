function Get-UniqueQueryName {
    <#
    .SYNOPSIS
    Returns a "Query{#}" name that does not already exist in the supplied list of query names,
    starting at -StartNumber and incrementing # until it is unique.

    .DESCRIPTION
    Used when duplicating a tab: the duplicate's tab name (Query{#}, from its open order) is put in
    the Display name field, but must not collide with an existing saved query. If "Query7" already
    exists in the query list, this returns the next free "Query{#}".
    #>
    [CmdLetBinding()]
    param(
        [string[]]$ExistingNames = @(),
        [int]$StartNumber = 1
    )

    $Taken = @{}
    foreach ($Name in $ExistingNames) {
        if (![string]::IsNullOrWhiteSpace($Name)) {
            $Taken[$Name.ToString().Trim()] = $true
        }
    }

    $Number = if ($StartNumber -lt 1) { 1 } else { $StartNumber }
    $Candidate = "Query{0}" -f $Number
    while ($Taken.ContainsKey($Candidate)) {
        $Number++
        $Candidate = "Query{0}" -f $Number
    }

    return $Candidate
}
