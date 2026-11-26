function Get-QueryManagerColumnDefinition {
    <#
    .SYNOPSIS
        The columns of the query manager's list, and the rows of the query details' Properties tab, in
        order: what each is called and where its value comes from.

    .DESCRIPTION
        One definition for both windows, so the list and the details show the same information under
        the same names.

          Name    The table column (and binding) name.
          Header  What the user sees.
          Field   The OData field of C_P_SQLTROUBLESHOOTING the value is read from, or "" for a value
                  that OData does not return.
          Kind    How the value is shown:
                    Id         the number
                    Text       as returned
                    Reference  a reference field: the referenced object's display name
                    Date       yyyy-MM-dd HH:mm:ss, in local time
                    Bool       Yes / No
                    Owner      who created / last changed the query. OData does not return these; they
                               come from the tenant's "SQL Troubleshooting" view - the same rows the
                               "Only my queries" filters use (Get-QueryOwnership).

    .OUTPUTS
        [PSCustomObject[]] @{ Name; Header; Field; Kind }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    @(
        , @("Id", "Id", "Id", "Id")
        , @("DisplayName", "Display name", "DisplayName", "Text")
        , @("Connection", "Connection", "C_SQLTROUBLESHOOTING_DATACONNECTION", "Reference")
        , @("CreateTime", "Created", "CreateTime", "Date")
        , @("CreatedBy", "Created by", "", "Owner")
        , @("ChangeTime", "Changed", "ChangeTime", "Date")
        , @("ChangedBy", "Changed by", "", "Owner")
        , @("Deleted", "Is Deleted", "Deleted", "Bool")
        , @("DeleteTime", "Deleted", "DeleteTime", "Date")
        , @("UId", "UId", "UId", "Text")
    ) | ForEach-Object {
        [PSCustomObject]@{ Name = $_[0]; Header = $_[1]; Field = $_[2]; Kind = $_[3] }
    }
}

function ConvertTo-QueryManagerRow {
    <#
    .SYNOPSIS
        One query object as the values its row shows, by column name (Get-QueryManagerColumnDefinition).

    .PARAMETER Query
        The query object, as OData returns it.

    .PARAMETER Ownership
        Who created and last changed each query, by query id (Get-QueryOwnership). Missing values stay
        empty.

    .OUTPUTS
        [ordered] name -> value; the Id as [long] (or $null), everything else as text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Query,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$Ownership = @{}
    )

    $Private:Owner = if ($null -ne $Ownership -and $null -ne $Query.Id) { $Ownership[[string]$Query.Id] } else { $null }
    $Private:Row = [ordered]@{}
    foreach ($Private:Column in @(Get-QueryManagerColumnDefinition)) {
        $Private:Value = if ($Private:Column.Kind -eq "Owner") { $Private:Owner.($Private:Column.Name) } else { $Query.($Private:Column.Field) }
        $Private:Row[$Private:Column.Name] = ConvertTo-QueryManagerColumnValue -Kind $Private:Column.Kind -Value $Private:Value
    }
    return $Private:Row
}

function ConvertTo-QueryManagerColumnValue {
    <#
    .SYNOPSIS
        A field value as its column shows it (see Get-QueryManagerColumnDefinition for the kinds).

    .DESCRIPTION
        PowerShell's JSON reader already turns OData's ISO 8601 times into DateTime; a time that is
        still text (another reader, another format) is parsed here, and shown as it came when it
        cannot be.

    .OUTPUTS
        [long] or $null for an Id; [string] for everything else.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Id", "Text", "Reference", "Date", "Bool", "Owner")]
        [string]$Kind,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        return $(if ($Kind -eq "Id") { $null } else { "" })
    }

    switch ($Kind) {
        "Id" { return [long]$Value }
        "Reference" { return $(if (-not [string]::IsNullOrWhiteSpace([string]$Value.DisplayName)) { [string]$Value.DisplayName } else { ConvertTo-QueryManagerValue -Value $Value }) }
        "Date" { return ConvertTo-QueryManagerDate -Value $Value }
        "Bool" { return $(if ([string]$Value -eq "True") { "Yes" } else { "No" }) }
    }
    return [string]$Value
}

function ConvertTo-QueryManagerDate {
    <#
    .SYNOPSIS
        A time as yyyy-MM-dd HH:mm:ss in local time, from a DateTime, a DateTimeOffset or ISO 8601
        text; any other text as it is.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )

    $Private:Format = "yyyy-MM-dd HH:mm:ss"
    $Private:Culture = [System.Globalization.CultureInfo]::InvariantCulture

    if ($Value -is [DateTime]) {
        # Only a time known to be UTC is converted; an unspecified one is shown as given rather than
        # shifted by a guess.
        $Private:Local = if ($Value.Kind -eq [DateTimeKind]::Utc) { $Value.ToLocalTime() } else { $Value }
        return $Private:Local.ToString($Private:Format, $Private:Culture)
    }
    if ($Value -is [DateTimeOffset]) {
        return $Value.LocalDateTime.ToString($Private:Format, $Private:Culture)
    }

    $Private:Parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string]$Value, $Private:Culture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Private:Parsed)) {
        return $Private:Parsed.LocalDateTime.ToString($Private:Format, $Private:Culture)
    }
    return [string]$Value
}

function Get-QueryOwnership {
    <#
    .SYNOPSIS
        Who created and who last changed each query, from the rows of the tenant's "SQL
        Troubleshooting" view (Get-SqlTroubleShooterView).

    .DESCRIPTION
        OData does not return the created-by and changed-by of a data object; that view does. Its
        columns are positional (c-<n>), and which is which lives in the tab's runtime data
        (DataobjdlgAspxAttributeMapping: SqlQueryDoId, SqlQueryCreatedBy, SqlQueryChangedBy), the same
        mapping the main window's "Only my queries" filters use.

    .PARAMETER ViewRow
        The view's rows.

    .PARAMETER Mapping
        @{ SqlQueryDoId; SqlQueryCreatedBy; SqlQueryChangedBy }: the column names.

    .OUTPUTS
        [hashtable] query id (as text) -> @{ CreatedBy; ChangedBy }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$ViewRow = @(),

        [Parameter(Mandatory = $true)]
        $Mapping
    )

    $Private:Ownership = @{}
    foreach ($Private:Row in @($ViewRow | Where-Object { $null -ne $_ })) {
        $Private:Id = [string]$Private:Row.($Mapping.SqlQueryDoId)
        if ([string]::IsNullOrWhiteSpace($Private:Id)) {
            continue
        }
        $Private:Ownership[$Private:Id] = [PSCustomObject]@{
            CreatedBy = [string]$Private:Row.($Mapping.SqlQueryCreatedBy)
            ChangedBy = [string]$Private:Row.($Mapping.SqlQueryChangedBy)
        }
    }
    return $Private:Ownership
}

function Test-QueryOwnedBy {
    <#
    .SYNOPSIS
        Whether a query passes the "Only my queries" filters: the same rule as the main window's
        query list (Update-QueryList).

    .DESCRIPTION
          neither filter       every query
          Created              queries the user created
          Last updated         queries the user changed last
          both                 queries the user created or changed last

        Without a user name to compare with, the filters cannot apply and every query passes, as in the
        main window.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Owner,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$UserName,

        [bool]$Created,

        [bool]$Updated
    )

    if (-not ($Created -or $Updated) -or [string]::IsNullOrWhiteSpace($UserName)) {
        return $true
    }

    $Private:IsCreator = $Created -and [string]$Owner.CreatedBy -eq $UserName
    $Private:IsChanger = $Updated -and [string]$Owner.ChangedBy -eq $UserName
    return $Private:IsCreator -or $Private:IsChanger
}
