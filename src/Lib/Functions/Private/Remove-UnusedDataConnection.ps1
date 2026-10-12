# The data connections that exist in the dropdown but address no deployed database once ODW ingestion
# is on. Named here rather than inline so the list is one thing to read, and one thing to change.
$Script:OdwUnusedDataConnectionName = @(
    "ODWMD"
    "Source System Data DB"
    "ODWS"
)

function Remove-UnusedDataConnection {
    <#
    .SYNOPSIS
        Drops the data connections that are published but unused, given the tenant's ingestion flag.

    .DESCRIPTION
        Issue #165. Not every published data connection points at a database that is actually deployed:
        when ODW ingestion is enabled, ODWMD, "Source System Data DB" and ODWS are offered by
        dataobjdlg.aspx and address nothing. Selecting one, or naming it in a query, fails against the
        tenant with nothing in the UI to suggest the database was never there.

        FILTERS ONLY ON AN EXPLICIT $true. $null - the flag was absent from the page, unparseable, or
        the probe failed - leaves the list exactly as it was, and so does $false. Hiding a database the
        user needs is a worse failure than offering one that does not work, which is today's behaviour
        anyway, so "we do not know" must never mean "remove them".

        MATCHED ON THE NAME, EXACTLY. The entries are "{Name} - {DoId}" and Get-DataConnectionReferenceList
        splits them from the RIGHT, precisely because a connection may legitimately be called
        "Reporting - archive". The comparison is against that parsed Name: case-insensitive and
        trimmed, never a substring. The trade-off is deliberate and worth stating, because it is the
        kind of thing a later reader would "fix" in the wrong direction:

          * a substring match would wrongly drop a legitimate "ODWS Reporting";
          * an exact match silently misses a renamed "ODWS (archive)".

        Missing a renamed one is the better failure: the user then sees a database that does not work,
        exactly as before this feature, rather than losing one they needed.

        Deliberately NOT folded into Get-DataConnectionOptionList. That function is a pure HTML parser
        with its own suite, and mixing a tenant-state decision into it would spoil what makes it
        testable.

    .PARAMETER OptionList
        The dropdown entries, as "{Name} - {DoId}". Null or empty yields an empty array.

    .PARAMETER IngestionEnabled
        The tenant's ingestion flag as three state: $true, $false, or $null for "not known".

    .OUTPUTS
        [string[]] the entries to keep, in their original order. Always an array, possibly empty.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$OptionList,

        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        [nullable[bool]]$IngestionEnabled
    )

    # No tracer preamble: the entries name the tenant's databases (issue #61 section 5).

    $Private:Option = @($OptionList | Where-Object { ![string]::IsNullOrWhiteSpace($_) })

    if ($Private:Option.Count -eq 0) {
        return , @()
    }

    # "Not known" and "off" both mean: leave it alone.
    if ($true -ne $IngestionEnabled) {
        return , $Private:Option
    }

    # The same parser the dropdown's other consumers use, so what is filtered here and what resolves
    # elsewhere can never disagree about where a name ends.
    # Not wrapped in @() - the function returns its array through the ", $array" idiom, and wrapping it
    # again nests the array one level deeper.
    $Private:Reference = Get-DataConnectionReferenceList -OptionList $Private:Option

    $Private:Removed = [System.Collections.Generic.List[string]]::new()
    $Private:Kept = [System.Collections.Generic.List[string]]::new()

    foreach ($Private:Entry in $Private:Reference) {
        $Private:Name = ([string]$Private:Entry.Name).Trim()

        if ($Private:Name -in $Script:OdwUnusedDataConnectionName) {
            # -in on a string array is case-insensitive, which is the comparison wanted here: the
            # tenant's casing is not something the user chose.
            $Private:Removed.Add($Private:Entry.FullName)
            continue
        }

        $Private:Kept.Add($Private:Entry.FullName)
    }

    # An entry the reference parser could not read is not in either list above, and dropping it here
    # would hide a connection for a reason that has nothing to do with ingestion. Put it back.
    foreach ($Private:Unparsed in $Private:Option) {
        if ($Private:Unparsed -notin $Private:Kept -and $Private:Unparsed -notin $Private:Removed) {
            $Private:Kept.Add($Private:Unparsed)
        }
    }

    if ($Private:Removed.Count -gt 0) {
        # DEBUG, and nothing user-visible: a notice would raise a question for every user on every
        # connect about behaviour that is correct. A user who expected ODWS can find the reason here.
        "ODW ingestion is enabled; filtered unused data connection(s): {0}" -f ($Private:Removed -join ", ") | Write-LogOutput -LogType DEBUG
    }

    # Original order preserved: it is the order Update-DataConnectionList sorted the dropdown into, and
    # the schema window shows its database nodes in the same order.
    return , @($Private:Option | Where-Object { $_ -in $Private:Kept })
}
