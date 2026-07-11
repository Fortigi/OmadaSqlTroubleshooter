function Get-IncrementedQueryName {
    <#
    .SYNOPSIS
    Returns a query name derived from -BaseName with a trailing number, incremented until it does
    not collide with -ExistingNames.

    .DESCRIPTION
    Used when duplicating a tab *including* its query: the copy keeps the source query's name but
    with the next free number appended/incremented, so the user only needs to click "New" to save
    it. If BaseName already ends in digits, those digits are the starting number and their
    zero-padding width is preserved ("Query09" -> "Query10"); otherwise "1" is appended
    ("Users" -> "Users1", "Report 3" -> "Report 4"). When BaseName is blank the "Query{#}" scheme
    is used instead. Matching against -ExistingNames is case-insensitive and ignores surrounding
    whitespace, mirroring Get-UniqueQueryName.
    #>
    [CmdLetBinding()]
    param(
        [string]$BaseName,
        [string[]]$ExistingNames = @()
    )

    $Taken = @{}
    foreach ($Name in $ExistingNames) {
        if (![string]::IsNullOrWhiteSpace($Name)) {
            $Taken[$Name.ToString().Trim()] = $true
        }
    }

    $Trimmed = if ($null -ne $BaseName) { $BaseName.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($Trimmed)) {
        $Prefix = "Query"
        $Width = 1
        $Number = [long]1
    }
    else {
        $Match = [regex]::Match($Trimmed, '^(?<Prefix>.*?)(?<Number>\d+)$')
        if ($Match.Success) {
            $Digits = $Match.Groups["Number"].Value
            $Prefix = $Match.Groups["Prefix"].Value
            $Width = $Digits.Length
            $Number = [long]$Digits + 1
        }
        else {
            $Prefix = $Trimmed
            $Width = 1
            $Number = [long]1
        }
    }

    $Candidate = "{0}{1}" -f $Prefix, ([string]$Number).PadLeft($Width, '0')
    while ($Taken.ContainsKey($Candidate)) {
        $Number++
        $Candidate = "{0}{1}" -f $Prefix, ([string]$Number).PadLeft($Width, '0')
    }

    return $Candidate
}
