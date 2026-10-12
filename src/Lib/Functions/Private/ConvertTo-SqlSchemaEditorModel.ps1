function ConvertTo-SqlSchemaEditorModel {
    <#
    .SYNOPSIS
        Turns a raw GetSqlSchema response into the two-level model the Monaco editor's completion
        provider consumes.

    .DESCRIPTION
        Extracted from Complete-SqlSchemaRetrieval by issue #158, which needs this shape for a second
        caller: a database other than the active one is pushed to the editor through
        setSchemaForDatabase(name, schema) and must be normalised exactly like the active one. A
        second copy of the splitting rules would be a second chance for a non-active database to
        complete differently from the active one.

        It is also the only part of that function that is pure, so extracting it is what makes the
        normalisation unit-testable without a WebView or a WPF tree.

        The rules are carried over unchanged from the code this replaces, and deliberately match
        Get-SqlSchemaModel (the index the validation pass resolves against):

        * The response is one object whose property names are "schema.table". Split on the FIRST dot
          only - a table name may legitimately contain one, the schema name is always in front.
        * Each column entry is "ColumnName DataType". Split on the first run of whitespace and keep
          the remainder intact, because the type itself may contain spaces ("nvarchar(50) NOT NULL").

    .PARAMETER SchemaResponse
        The response object as cached in $Script:SqlSchemaCache: the payload is on its .d property.
        Null, an ErrorRecord, or a response with no .d yields an empty model, which serialises to
        "{}" and is what tells the editor this database has no completions rather than leaving it
        with a previous database's.

    .OUTPUTS
        [hashtable] schema -> table -> @( [PSCustomObject]@{ n = column name; t = data type } ).

        The column arrays are wrapped in @() so a single-column table still serialises as a JSON
        array rather than as a lone object - the editor's normalizeColumn only maps arrays.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        $SchemaResponse
    )

    # No tracer preamble: the parameter is the tenant's schema, which names every table and column in
    # the customer's database (issue #61 section 5).

    process {
        $SchemaObject = @{}

        if ($null -eq $SchemaResponse -or $SchemaResponse -is [System.Management.Automation.ErrorRecord]) {
            return $SchemaObject
        }

        $Payload = $SchemaResponse.d
        if ($null -eq $Payload) {
            return $SchemaObject
        }

        # ONE pass over the tables, grouping them by schema as it goes. This used to collect the schema
        # names first and then filter every table again for each schema, with a pipeline per column -
        # 1.5 s for a 565-table database on the UI thread, against 0.4 s for this, for the same model.
        # PSObject.Properties rather than Get-Member: same NoteProperties, without the cmdlet. One
        # compiled regex for every column, rather than the -split operator per entry.
        $ColumnSplitter = [regex]::new("\s+")
        foreach ($Property in $Payload.PSObject.Properties) {
            # NoteProperties only, which is exactly what Get-Member -MemberType NoteProperty returned:
            # a payload that is not an object (a string, say) has CLR properties such as Length too.
            if ($Property.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty) {
                continue
            }

            $Part = $Property.Name.Split(".", 2)
            $SchemaName = $Part[0]

            if (-not $SchemaObject.ContainsKey($SchemaName)) {
                $SchemaObject[$SchemaName] = @{}
            }

            # A name without a dot has a schema and no table, which is what the two-pass version made
            # of it too: the schema, empty.
            if ($Part.Count -lt 2) {
                continue
            }

            $ColumnList = [System.Collections.Generic.List[object]]::new()
            foreach ($Entry in @($Property.Value)) {
                $ColumnPart = $ColumnSplitter.Split(([string]$Entry).Trim(), 2)
                $ColumnList.Add([PSCustomObject][Ordered]@{
                        n = $ColumnPart[0]
                        t = if ($ColumnPart.Count -gt 1) { $ColumnPart[1].Trim() } else { "" }
                    })
            }

            $SchemaObject[$SchemaName][$Part[1]] = $ColumnList.ToArray()
        }

        return $SchemaObject
    }
}

function Get-SqlSchemaEditorJson {
    <#
    .SYNOPSIS
        The editor model of a cached schema as compact JSON, built once per response.

    .DESCRIPTION
        Every completion of a schema request pushes the schema to the editor - also when it is served
        from the cache, because the CALLER (a tab switch, the schema window opening, a database node
        being expanded) still has to be served, and each tab has its own editor. Converting the response
        again for every one of those cost about a second per large database on the UI thread, for a
        string that cannot have changed. So the string is kept beside the response, under the same
        cache key.

        Complete-SqlSchemaRetrieval drops the entry whenever it stores a DIFFERENT response object for
        the key (a fresh fetch, a refresh), and Reset-SqlSchemaCache drops the pool's entries, so a
        string never outlives the response it was built from.

        -Compress: the editor parses the payload, and nobody reads it. The indented form took 3.5 times
        as long and 35,000 lines for a large database; Complete-SqlSchemaRetrieval still logs it at
        VERBOSE2 for whoever needs to read it.

    .PARAMETER SchemaCacheKey
        The "<SessionKey>|<DoId>" key the response is cached under. Empty means "do not memoise".

    .PARAMETER SchemaResponse
        The response the JSON is built from when it is not memoised yet.

    .OUTPUTS
        [string] the JSON the editor's setSchema / setSchemaForDatabase receive.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SchemaCacheKey,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $SchemaResponse
    )

    # No tracer preamble: called once per schema push, and its result is the tenant's schema.

    if ($null -eq $Script:SqlSchemaEditorJsonCache) {
        $Script:SqlSchemaEditorJsonCache = @{}
    }

    if (![string]::IsNullOrWhiteSpace($SchemaCacheKey) -and $Script:SqlSchemaEditorJsonCache.ContainsKey($SchemaCacheKey)) {
        return $Script:SqlSchemaEditorJsonCache[$SchemaCacheKey]
    }

    $Private:Json = ConvertTo-SqlSchemaEditorModel -SchemaResponse $SchemaResponse | ConvertTo-Json -Depth 5 -Compress

    if (![string]::IsNullOrWhiteSpace($SchemaCacheKey)) {
        $Script:SqlSchemaEditorJsonCache[$SchemaCacheKey] = $Private:Json
    }

    return $Private:Json
}
