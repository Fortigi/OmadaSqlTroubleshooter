function Get-SqlSchemaModel {
    <#
    .SYNOPSIS
        Turns a raw GetSqlSchema response into the lookup the schema validation pass resolves
        identifiers against.

    .DESCRIPTION
        The schema pass of issue #61 needs three questions answered quickly and case-insensitively:
        does this schema exist, does this table exist in it, and does this column exist on that
        table. The response from SyntaxHighlighting.asmx/GetSqlSchema answers none of them directly -
        it is one object whose property names are "schema.table" and whose values are arrays of
        "ColumnName DataType" strings - so it is indexed here, once per response, rather than
        re-scanned per identifier.

        The same normalisation Complete-SqlSchemaRetrieval already does for the editor's IntelliSense
        (split the property name on the FIRST dot, split each column entry on the first run of
        whitespace) is applied here, deliberately, so the pass sees exactly the schema the completion
        list sees. A resolver that disagreed with IntelliSense about what exists would be worse than
        no resolver.

        Every lookup is a PowerShell hashtable, which compares string keys case-insensitively - which
        is also how SQL Server resolves identifiers under the usual collations.

    .PARAMETER SchemaResponse
        The response object as cached in $Script:SqlSchemaCache: the payload is on its .d property.
        Null, an ErrorRecord, or a response with no .d yields $null - "no schema" rather than an
        empty schema, because an empty schema would make every identifier in the script a miss.

    .OUTPUTS
        [PSCustomObject] with

            Table        "schema.table" -> @{ Schema; Table; Column = @{ name = type } }
            BySchema     schema -> @{ table -> the same entry }
            ByTableName  table  -> @( every entry with that table name, across schemas )

        or $null when the response carries no schema.
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
        if ($null -eq $SchemaResponse -or $SchemaResponse -is [System.Management.Automation.ErrorRecord]) {
            return $null
        }

        $Payload = $SchemaResponse.d
        if ($null -eq $Payload) {
            return $null
        }

        $Table = @{}
        $BySchema = @{}
        $ByTableName = @{}

        foreach ($Property in @($Payload | Get-Member -MemberType NoteProperty)) {
            $FullName = $Property.Name

            # Split on the FIRST dot only: a table name may legitimately contain one, the schema name
            # is always the part in front.
            $Part = $FullName.Split(".", 2)
            if ($Part.Count -ne 2 -or [string]::IsNullOrWhiteSpace($Part[0]) -or [string]::IsNullOrWhiteSpace($Part[1])) {
                continue
            }

            $SchemaName = $Part[0]
            $TableName = $Part[1]

            $Column = @{}
            foreach ($Entry in @($Payload.$FullName)) {
                if ([string]::IsNullOrWhiteSpace([string]$Entry)) {
                    continue
                }

                $ColumnPart = ([string]$Entry).Trim() -split "\s+", 2
                $ColumnName = $ColumnPart[0]
                if ([string]::IsNullOrWhiteSpace($ColumnName)) {
                    continue
                }

                $Column[$ColumnName] = if ($ColumnPart.Count -gt 1) { $ColumnPart[1].Trim() } else { "" }
            }

            $Entry = [PSCustomObject][Ordered]@{
                Schema = $SchemaName
                Table  = $TableName
                Column = $Column
            }

            $Table[$FullName] = $Entry

            if (-not $BySchema.ContainsKey($SchemaName)) {
                $BySchema[$SchemaName] = @{}
            }
            $BySchema[$SchemaName][$TableName] = $Entry

            if (-not $ByTableName.ContainsKey($TableName)) {
                $ByTableName[$TableName] = [System.Collections.Generic.List[object]]::new()
            }
            $ByTableName[$TableName].Add($Entry)
        }

        if ($Table.Count -eq 0) {
            # A response that produced no tables is indistinguishable from a failed one as far as the
            # pass is concerned, and resolving against it would flag every identifier in the script.
            return $null
        }

        # Count only, never the names (issue #61 section 5).
        "Indexed the cached SQL schema: {0} table(s) across {1} schema(s)." -f $Table.Count, $BySchema.Count | Write-LogOutput -LogType DEBUG

        return [PSCustomObject]@{
            Table       = $Table
            BySchema    = $BySchema
            ByTableName = $ByTableName
        }
    }
}
