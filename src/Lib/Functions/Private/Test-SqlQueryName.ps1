function Test-SqlQueryName {
    <#
    .SYNOPSIS
        Checks a name the user typed for a query (rename, or saving an ad-hoc query) before anything is
        sent to the tenant.

    .DESCRIPTION
        Only what can be decided locally is decided here; the tenant remains the authority on whether a
        name is taken (Rename-SqlQuery and Save-Query still probe for it), because the cached query
        list can be stale and can be filtered by "Filter my queries".

          - The name is trimmed. Leading or trailing blanks are never intended and would make two
            visually identical names differ.
          - An empty name is refused: a query is listed, and saved, under its name.
          - A name starting with TMP_ is refused. TMP_<InstanceGuid> is the temporary object the
            execute pipeline creates and deletes around every ad-hoc or selection execute; a user query
            with that prefix would be indistinguishable from one left behind by a crashed instance.
          - A name that is unchanged (rename only) is reported as such, so the caller can skip the
            request instead of treating it as a clash with itself.
          - A name already present in the known query list is refused, compared case-insensitively.

    .PARAMETER Name
        The name as typed.

    .PARAMETER ExistingNames
        Display names of the queries this tab knows about.

    .PARAMETER CurrentName
        The query's current name when renaming; omitted when saving a new query.

    .OUTPUTS
        [PSCustomObject] @{ IsValid; IsUnchanged; Name; Message }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string[]]$ExistingNames = @(),

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CurrentName
    )

    $Private:Trimmed = ([string]$Name).Trim()
    $Private:Result = [PSCustomObject]@{
        IsValid     = $false
        IsUnchanged = $false
        Name        = $Private:Trimmed
        Message     = $null
    }

    if ($Private:Trimmed.Length -eq 0) {
        $Private:Result.Message = "The query name cannot be empty."
        return $Private:Result
    }

    if ($Private:Trimmed.StartsWith("TMP_", [System.StringComparison]::OrdinalIgnoreCase)) {
        $Private:Result.Message = "Query names starting with 'TMP_' are reserved for the temporary query objects this application creates."
        return $Private:Result
    }

    if (![string]::IsNullOrWhiteSpace($CurrentName) -and $Private:Trimmed -ceq $CurrentName.Trim()) {
        $Private:Result.IsUnchanged = $true
        $Private:Result.IsValid = $true
        return $Private:Result
    }

    $Private:Clash = @($ExistingNames | Where-Object {
            ![string]::IsNullOrWhiteSpace($_) -and $_.Trim() -eq $Private:Trimmed -and $_.Trim() -ne ([string]$CurrentName).Trim()
        })
    if ($Private:Clash.Count -gt 0) {
        $Private:Result.Message = "A query named '{0}' already exists." -f $Private:Trimmed
        return $Private:Result
    }

    $Private:Result.IsValid = $true
    return $Private:Result
}
