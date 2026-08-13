function ConvertTo-WildcardFilterPattern {
    <#
    .SYNOPSIS
    Converts a filter value typed by the user into a PowerShell -like pattern.

    .DESCRIPTION
    Used by the SQL schema tree filter. The value is matched as a case-insensitive substring, so it
    is wrapped in wildcards: "Object" becomes "*Object*". When the value already contains "*" or "?"
    the user is in control and those characters keep their wildcard meaning, so "tbl*Type" becomes
    "*tbl*Type*". Any other character is escaped, because "[" and "]" open a character class in a
    -like pattern.

    A null, empty or whitespace-only value returns $null, which callers treat as "no filter".
    Matching itself is case-insensitive because -like is case-insensitive by default.
    #>
    [CmdLetBinding()]
    param(
        [string]$FilterValue
    )

    $Trimmed = if ($null -ne $FilterValue) { $FilterValue.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($Trimmed)) {
        return $null
    }

    $EscapedCharacters = $Trimmed.ToCharArray() | ForEach-Object {
        if ($_ -eq "*" -or $_ -eq "?") {
            [string]$_
        }
        else {
            [System.Management.Automation.WildcardPattern]::Escape([string]$_)
        }
    }

    return "*{0}*" -f ($EscapedCharacters -join "")
}
