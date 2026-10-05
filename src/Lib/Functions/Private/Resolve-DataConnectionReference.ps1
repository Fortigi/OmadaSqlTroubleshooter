function Get-DataConnectionReferenceList {
    <#
    .SYNOPSIS
        Parses the data connection dropdown entries into { Name; DoId; FullName } objects.

    .DESCRIPTION
        The "{Name} - {DoId}" format was being taken apart by the same regex in three places by the
        time issue #158 needed a fourth: Resolve-DataConnectionReference to find one connection,
        Get-UnresolvedDatabaseMessage to list the available names, and now the schema window to put a
        node on the tree for every connection. All of them now call this.

        The entry is split from the RIGHT, which is the whole reason this needs care. A data
        connection may legitimately be called "Reporting - archive", and splitting from the left would
        make its name "Reporting" and its DoId "archive - 1001572". The DoId is the trailing run of
        digits, so anchoring the pattern at the end is what keeps such a name resolvable.

        Order is preserved - it is the order Update-DataConnectionList sorted the dropdown into, and
        the schema window shows its database nodes in the same order as the dropdown.

    .PARAMETER OptionList
        The dropdown entries. Null, empty, and entries that do not match the format are skipped
        rather than being reported: an unparseable entry is not something the user can act on.

    .OUTPUTS
        [PSCustomObject[]] with Name (the connection's own casing), DoId and FullName (the entry as
        it appears in the dropdown). Always an array, possibly empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$OptionList
    )

    # No tracer preamble: the entries name the tenant's databases (issue #61 section 5).

    $Result = [System.Collections.Generic.List[object]]::new()

    foreach ($Option in @($OptionList)) {
        if ([string]::IsNullOrWhiteSpace($Option)) {
            continue
        }

        if ($Option -notmatch '^(?<Name>.*) - (?<DoId>\d+)$') {
            continue
        }

        $Result.Add([PSCustomObject]@{
                Name     = $Matches.Name
                DoId     = $Matches.DoId
                FullName = $Option
            })
    }

    return , $Result.ToArray()
}

function Resolve-DataConnectionReference {
    <#
    .SYNOPSIS
        Resolves a database name written in a query onto the data connection DoId that Omada's query
        data object and GetPagingData actually work with.

    .DESCRIPTION
        GetPagingData and the SQL query data object address a data connection by DoId, never by
        name, but issue #152 lets the user write the name. The dropdown already holds both: every
        entry is the "{Name} - {DoId}" string Get-DataConnectionOptionList produces, so this is an
        in-memory lookup and costs no round trip (#152 section 4).

        THE NAME IS THE DATA CONNECTION'S NAME, not necessarily the physical database name. That is
        the issue's own open question 1, settled deliberately: Omada exposes only name, DoId and uid
        on dataobjdlg.aspx, so there is no cheap way to ask a connection what database it points at.
        A tenant whose connections are named differently from its databases will therefore write the
        connection name, and the feature's documentation says so.

        Matching is case-insensitive, as T-SQL identifier comparison is under the usual collations.

        The "{Name} - {DoId}" string is split from the RIGHT. A data connection may legitimately be
        called "Reporting - archive", and splitting from the left would make its name "Reporting"
        and its DoId "archive - 1001572". The DoId is the trailing run of digits, so anchoring the
        pattern at the end is what keeps such a name resolvable.

    .PARAMETER Name
        The database name as written in the query, with brackets already removed by the parser.

    .PARAMETER OptionList
        The dropdown entries, each "{Name} - {DoId}". Null or empty yields $null.

    .OUTPUTS
        [PSCustomObject] with Name (the connection's own casing), DoId and FullName (the entry as it
        appears in the dropdown), or $null when the name matches no connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name,
        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$OptionList
    )

    # No tracer preamble: the parameters name the tenant's databases (issue #61 section 5).

    if ([string]::IsNullOrWhiteSpace($Name) -or $null -eq $OptionList) {
        return $null
    }

    foreach ($Reference in (Get-DataConnectionReferenceList -OptionList $OptionList)) {
        if ($Reference.Name -ne $Name) {
            # -ne on strings is case-insensitive in PowerShell, which is the comparison wanted here.
            continue
        }

        return $Reference
    }

    return $null
}
