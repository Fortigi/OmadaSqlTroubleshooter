function Get-QueryColumnSqlTypeMap {
    <#
    .SYNOPSIS
        Maps the column names a query can produce to the SQL types the cached schema declares for
        them.

    .DESCRIPTION
        Priority 1 of issue #103's resolution order, and the fix for issue #120. PR #106 left this a
        seam: Get-QueryResultValueKind read a declared type, Format-QueryResultSelection passed one
        along, and nothing ever produced one - so the CLR type of the deserialised JSON value was the
        only source in play. Against a response that types every column as a string, that source
        answers "String" for every column and the whole feature reduces to quoting everything.

        This resolves a grid column back to a declared type WITHOUT a request: the executed query is
        parsed with the ScriptDom already used by the validation passes of issue #61, and the tables
        it names are resolved against the schema the application already fetched for IntelliSense.

        THE RULE IS "SAY NOTHING UNLESS IT IS CERTAIN". A wrong declared type is worse than none -
        it is what could turn a string into an unquoted number - so every source of doubt drops the
        column from the map rather than guessing:

          * A column name declared by more than one of the query's tables with DIFFERENT types is
            dropped. Same name, same type, several tables is not a doubt and is kept.
          * A name used as a SELECT alias for anything other than the identically named column is
            dropped. "COUNT(*) AS Id" must never inherit the type of a real Id column.
          * Names the script defines itself - CTEs, temp tables, table variables - are not resolved
            against the database, and neither are three- and four-part names. This mirrors
            Get-SqlSchemaDiagnostic's false-positive rule, for the same reason.
          * No ScriptDom, no cached schema, or a query that does not parse yields an empty map.

        The map is keyed case-insensitively, which is how SQL Server resolves identifiers under the
        usual collations and how Get-SqlSchemaModel already indexes them.

        Nothing here logs an identifier: the query is the user's and the schema is the tenant's
        (issue #61 section 5).

    .PARAMETER SqlText
        The executed query.

    .PARAMETER SchemaModel
        The indexed schema from Get-SqlSchemaModel. Null yields an empty map.

    .PARAMETER ParserVersion
        An explicit TSqlNNNParser, passed through to Get-SqlScriptFragment.

    .OUTPUTS
        [hashtable] column name -> declared SQL type, for example @{ Id = "int" }. Empty when
        nothing could be resolved.

    .NOTES
        No tracer preamble: the parameters are the user's query and the tenant's schema.
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $SchemaModel,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ParserVersion
    )

    $Empty = @{}

    if ($null -eq $SchemaModel -or [string]::IsNullOrWhiteSpace($SqlText)) {
        return $Empty
    }

    $Parsed = Get-SqlScriptFragment -SqlText $SqlText -ParserVersion $ParserVersion
    if ($null -eq $Parsed -or $Parsed.Status -ne "Ok" -or $null -eq $Parsed.Fragment) {
        return $Empty
    }

    $Fragment = $Parsed.Fragment

    # Names the script defines itself. A CTE called "IDENTITY" is not the tenant's IDENTITY table,
    # and resolving it as one would type the copy from the wrong columns entirely.
    $ScriptDefined = @{}
    foreach ($Cte in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "CommonTableExpression")) {
        if (![string]::IsNullOrWhiteSpace($Cte.ExpressionName.Value)) {
            $ScriptDefined[$Cte.ExpressionName.Value] = $true
        }
    }

    # Every declared type seen for a name, so a disagreement can be detected rather than resolved by
    # whichever table happened to be walked last.
    $TypeByColumn = @{}
    $DroppedColumn = @{}

    foreach ($TableReference in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "NamedTableReference")) {
        $Identifier = @($TableReference.SchemaObject.Identifiers)
        if ($Identifier.Count -eq 0 -or $Identifier.Count -ge 3) {
            continue
        }

        $BaseName = [string]$Identifier[-1].Value
        if ([string]::IsNullOrWhiteSpace($BaseName) -or $BaseName.StartsWith("#") -or $BaseName.StartsWith("@")) {
            continue
        }

        if ($Identifier.Count -eq 1 -and $ScriptDefined.ContainsKey($BaseName)) {
            continue
        }

        $IsAmbiguous = $false
        $Entry = Resolve-SqlSchemaTable -SchemaModel $SchemaModel -Identifier $Identifier -Ambiguous ([ref]$IsAmbiguous)
        if ($null -eq $Entry -or $IsAmbiguous) {
            continue
        }

        foreach ($ColumnName in @($Entry.Column.Keys)) {
            $DeclaredType = [string]$Entry.Column[$ColumnName]

            # Both spellings: the name as the database declares it, and the name the grid would bind
            # it under if the response had to go through Invoke-SanitizeJsonKeys. See
            # Get-SanitizedBindingName - a column called "Order Date" binds as "Order_Date", and a map
            # keyed only by the declared spelling would silently never answer for it.
            foreach ($Key in @(Get-ColumnLookupName -Name $ColumnName)) {
                if ([string]::IsNullOrWhiteSpace($DeclaredType)) {
                    $DroppedColumn[$Key] = $true
                    continue
                }

                if (-not $TypeByColumn.ContainsKey($Key)) {
                    $TypeByColumn[$Key] = $DeclaredType
                    continue
                }

                # Two columns reaching the same lookup name with different types - two tables in the
                # query declaring the same column differently, or two differently named columns that
                # sanitise to the same binding name. Which one the grid column came from is not
                # knowable from the name, so neither is its type.
                if ($TypeByColumn[$Key] -ne $DeclaredType) {
                    $DroppedColumn[$Key] = $true
                }
            }
        }
    }

    foreach ($Alias in @(Get-QuerySelectAliasName -Fragment $Fragment)) {
        # Both spellings again, and here it is not merely a missed opportunity: an alias written
        # "[Total Count]" binds as "Total_Count", so dropping only the declared spelling would let
        # that column inherit the declared type of a real "Total_Count" column.
        foreach ($Key in @(Get-ColumnLookupName -Name $Alias)) {
            $DroppedColumn[$Key] = $true
        }
    }

    $Map = @{}
    foreach ($ColumnName in @($TypeByColumn.Keys)) {
        if ($DroppedColumn.ContainsKey($ColumnName)) {
            continue
        }

        $Map[$ColumnName] = $TypeByColumn[$ColumnName]
    }

    # Counts only, never the names.
    "Resolved {0} of {1} candidate column name(s) to a declared SQL type for the copy path." -f $Map.Count, $TypeByColumn.Count | Write-LogOutput -LogType DEBUG

    return $Map
}

function Get-ColumnLookupName {
    <#
    .SYNOPSIS
        The names a schema column or a SELECT alias can be looked up under from the grid.

    .DESCRIPTION
        A grid column is keyed by its binding path, and the binding path is not always the name the
        database uses. When the tenant returns keys WPF cannot bind, Complete-ExecuteQueryResult
        re-binds the response through Invoke-SanitizeJsonKeys, which replaces every character outside
        [A-Za-z0-9_-] with an underscore - so "Order Date" arrives in the grid as "Order_Date".

        Both spellings are therefore returned, deduplicated, and the caller records each of them. A
        name that needs no sanitising yields one entry and costs nothing.

    .PARAMETER Name
        The declared column name or alias.

    .OUTPUTS
        [string[]] the name, plus its sanitised form when that differs.

    .NOTES
        No tracer preamble: the parameter is a tenant identifier.
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return @()
    }

    # The rule Invoke-SanitizeObject applies, and it has to stay the same rule: a copy that drifted
    # would resolve a column the grid binds under a different name.
    $Sanitized = $Name -replace '[^A-Za-z0-9_\-]', "_"

    if ($Sanitized -ceq $Name) {
        return @($Name)
    }

    return @($Name, $Sanitized)
}

function Get-QuerySelectAliasName {
    <#
    .SYNOPSIS
        Returns the SELECT aliases that must not inherit a table column's declared type.

    .DESCRIPTION
        A grid column carries the name of the result column, which for an aliased select element is
        the alias. "COUNT(*) AS Id" produces a column called Id that has nothing to do with the Id
        column of any table in the query, and typing it from one would be exactly the kind of
        confident wrong answer this resolution refuses to give.

        An alias that renames a column to itself - "SELECT Id AS Id" - is not a shadow and is left
        alone. Everything else is reported, whether or not a table in the query happens to declare
        that name; the caller drops the reported names from its map, so a name nobody declares costs
        nothing.

    .PARAMETER Fragment
        The parsed script.

    .OUTPUTS
        [string[]] the alias names.

    .NOTES
        No tracer preamble: the fragment is the user's query.
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment
    )

    $Alias = [System.Collections.Generic.List[string]]::new()

    foreach ($SelectElement in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "SelectScalarExpression")) {
        $AliasName = [string]$SelectElement.ColumnName.Value
        if ([string]::IsNullOrWhiteSpace($AliasName)) {
            continue
        }

        $Expression = $SelectElement.Expression
        if ($null -ne $Expression -and $Expression.GetType().Name -eq "ColumnReferenceExpression") {
            $Part = @($Expression.MultiPartIdentifier.Identifiers)
            if ($Part.Count -gt 0 -and [string]$Part[-1].Value -eq $AliasName) {
                continue
            }
        }

        $Alias.Add($AliasName)
    }

    return @($Alias)
}

function Get-ActiveQueryColumnSqlTypeMap {
    <#
    .SYNOPSIS
        The declared-type map for the query whose result is currently in the grid.

    .DESCRIPTION
        The $Script:-state half of the resolution, kept apart from Get-QueryColumnSqlTypeMap so that
        every decision in it stays testable without an application.

        $Script:RunTimeData.QueryText is the editor text as it was when the query was last executed
        or saved - Invoke-ExecuteQuery writes it on the way to dispatching the execute - which is the
        closest thing to "the query the grid is showing" that exists outside the execute pipeline.
        An execute-selection run leaves the FULL script here rather than the selected statement; that
        is harmless, because a wider script can only add candidate tables, and a name two of them
        disagree about is dropped.

        It resolves to nothing at all - not to a guess - when the schema has not been fetched, when
        ScriptDom is not installed, or when ArrayCopyUseColumnSchema is off.

    .OUTPUTS
        [hashtable] column name -> declared SQL type. Empty when nothing could be resolved.

    .NOTES
        No tracer preamble: this is on the clipboard path and reads the user's query.
    #>

    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $Setting = Get-ArrayCopySetting
        if ($null -eq $Setting -or -not $Setting.UseColumnSchema) {
            return @{}
        }

        $SchemaModel = Get-ActiveSqlSchemaModel
        if ($null -eq $SchemaModel) {
            return @{}
        }

        $QueryText = $null
        if ($null -ne $Script:RunTimeData -and $Script:RunTimeData.QueryText -is [string]) {
            $QueryText = [string]$Script:RunTimeData.QueryText
        }

        if ([string]::IsNullOrWhiteSpace($QueryText)) {
            return @{}
        }

        $ParserVersion = $null
        $ValidationSetting = Get-SqlValidationSetting
        if ($null -ne $ValidationSetting) {
            $ParserVersion = [string]$ValidationSetting.ParserVersion
        }

        return Get-QueryColumnSqlTypeMap -SqlText $QueryText -SchemaModel $SchemaModel -ParserVersion $ParserVersion
    }
    catch {
        # No declared type is a supported state - it is the state every copy was in before this
        # change - so a failure degrades to it. The message can name tenant objects, so it is not
        # logged.
        "The declared column types could not be resolved for this copy; the value types are used instead." | Write-LogOutput -LogType DEBUG
        return @{}
    }
}
