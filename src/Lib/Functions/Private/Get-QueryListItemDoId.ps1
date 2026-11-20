function Get-QueryListItemDoId {
    <#
    .SYNOPSIS
        The DoId a query dropdown entry stands for.

    .DESCRIPTION
        Update-QueryList writes each entry as "<DisplayName> - <DoId>", and a display name may itself
        contain " - ", so the id is whatever follows the LAST separator - the same rule
        Set-ConfigProperty applies when it parses an entry into CurrentSqlQuery.

    .PARAMETER Content
        The entry's Content.

    .OUTPUTS
        [string] The DoId, or $null when the entry has no id suffix.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Content
    )

    $Private:Text = [string]$Content
    $Private:Index = $Private:Text.LastIndexOf(" - ")
    if ($Private:Index -lt 0) {
        return $null
    }

    $Private:Id = $Private:Text.Substring($Private:Index + 3).Trim()
    if ($Private:Id -notmatch '^\d+$') {
        return $null
    }

    return $Private:Id
}
