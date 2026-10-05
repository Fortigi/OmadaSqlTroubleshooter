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

        $Property = @($Payload | Get-Member -MemberType NoteProperty)

        $SchemaNameList = @($Property.Name | ForEach-Object { $_.Split(".", 2)[0] } | Select-Object -Unique)
        foreach ($SchemaName in $SchemaNameList) {
            $TableObject = @{}

            foreach ($Table in @($Property | Where-Object { $_.Name -like ("{0}.*" -f $SchemaName) })) {
                $TableFullName = $Table.Name
                $TableName = $TableFullName.Split(".", 2)[1]

                $TableObject[$TableName] = @($Payload.$TableFullName | ForEach-Object {
                        $Part = $_.Trim() -split "\s+", 2
                        [PSCustomObject][Ordered]@{
                            n = $Part[0]
                            t = if ($Part.Count -gt 1) { $Part[1].Trim() } else { "" }
                        }
                    })
            }

            $SchemaObject[$SchemaName] = $TableObject
        }

        return $SchemaObject
    }
}
