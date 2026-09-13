function Get-SqlSchemaDiagnostic {
    <#
    .SYNOPSIS
        Resolves the tables and columns a parsed script names against the schema already cached for
        the current data connection, and reports what it could not find.

    .DESCRIPTION
        The second validation pass of issue #61. It makes no request: the application already fetched
        this schema for the editor's IntelliSense, so the tool already knows that dbo.Peson is not a
        table - it simply never said so (acceptance criteria 2 and 5).

        Everything here is a WARNING and nothing here gates execution (acceptance criterion 4), for
        two reasons the wording is chosen to reflect. GetSqlSchema's coverage of views, table-valued
        functions and synonyms is not guaranteed, and the cache can be older than the database. So a
        miss is reported as "not found in the cached schema", never as "does not exist".

        THE FALSE-POSITIVE RULE. A pass that cries wolf gets switched off, and then it protects
        nobody - so wherever this cannot be certain, it says nothing:

          * Names the script defines itself - CTEs, SELECT INTO targets, temp tables, table variables
            and derived-table aliases - are never resolved against the database.
          * Three-part and four-part names are skipped: a cross-database or linked-server object is
            not in this schema and its absence proves nothing.
          * A query scope containing ANY source this pass cannot see through - a derived table, a
            CTE, a table-valued function, PIVOT, OPENJSON, a table variable, a temp table, or a table
            that did not resolve - has its COLUMN checks suppressed entirely. The columns of such a
            source are unknown, so every unqualified column in that scope could legitimately be one
            of them. Table checks still run; they do not depend on the scope.
          * A qualifier that matches no source in scope is skipped rather than flagged.
          * Anything inside dynamic SQL is invisible to this pass by construction: the parser never
            sees the string's contents.

        The result is a pass that is quiet on a complex query and precise on a simple one, which is
        the right way round - the simple query is where a typo is both most likely and most annoying.

    .PARAMETER Fragment
        The parsed script from Get-SqlScriptFragment. Null yields no diagnostics.

    .PARAMETER SchemaModel
        The indexed schema from Get-SqlSchemaModel. Null yields no diagnostics: with no schema in
        hand, every identifier would be a miss.

    .PARAMETER Source
        The value written to each diagnostic's Source field, which is what makes a schema warning
        distinguishable from a syntax error on the one shared diagnostics channel.

    .OUTPUTS
        Marker-shaped [PSCustomObject]s with Line, Column, EndLine, EndColumn, Severity, Message,
        Source and Number. Number is 0: these diagnostics have no SQL Server error number.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $SchemaModel,
        [Parameter(Mandatory = $false)]
        [string]$Source = "SQL schema"
    )

    # No tracer preamble: the fragment is the user's query and the model is the tenant's schema
    # (issue #61 section 5). Nothing below logs an identifier at any level.

    if ($null -eq $Fragment -or $null -eq $SchemaModel) {
        return @()
    }

    try {
        $Diagnostic = [System.Collections.Generic.List[PSCustomObject]]::new()

        # ------------------------------------------------------------------ names the script defines
        # Collected across the WHOLE script rather than per scope. A name defined anywhere is a name
        # this pass must not resolve against the database anywhere - erring towards silence.
        $ScriptDefined = @{}

        foreach ($Cte in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "CommonTableExpression")) {
            if (![string]::IsNullOrWhiteSpace($Cte.ExpressionName.Value)) {
                $ScriptDefined[$Cte.ExpressionName.Value] = $true
            }
        }

        foreach ($Select in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "SelectStatement")) {
            $IntoName = Get-SqlSchemaObjectBaseName -SchemaObject $Select.Into
            if (![string]::IsNullOrWhiteSpace($IntoName)) {
                $ScriptDefined[$IntoName] = $true
            }
        }

        foreach ($Create in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "CreateTableStatement")) {
            $CreatedName = Get-SqlSchemaObjectBaseName -SchemaObject $Create.SchemaObjectName
            if (![string]::IsNullOrWhiteSpace($CreatedName)) {
                $ScriptDefined[$CreatedName] = $true
            }
        }

        # ---------------------------------------------------------------------------- table checking
        foreach ($TableReference in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "NamedTableReference")) {
            $Identifier = @($TableReference.SchemaObject.Identifiers)
            if ($Identifier.Count -eq 0 -or $Identifier.Count -ge 3) {
                # Three or more parts is a cross-database or linked-server name. This schema says
                # nothing about it, so neither does this pass.
                continue
            }

            $BaseName = [string]$Identifier[-1].Value
            if ([string]::IsNullOrWhiteSpace($BaseName) -or $BaseName.StartsWith("#") -or $BaseName.StartsWith("@")) {
                continue
            }

            if ($Identifier.Count -eq 1 -and $ScriptDefined.ContainsKey($BaseName)) {
                continue
            }

            $Resolved = Resolve-SqlSchemaTable -SchemaModel $SchemaModel -Identifier $Identifier
            if ($null -ne $Resolved) {
                continue
            }

            $Marker = Get-SqlFragmentMarker -Fragment $TableReference.SchemaObject
            if ($null -eq $Marker) {
                continue
            }

            $Diagnostic.Add((New-SqlSchemaDiagnosticItem -Marker $Marker -Source $Source -Message (
                    "'{0}' is not found in the cached schema for this data connection. Check the name, or refresh the schema if the database has changed since you connected." -f (($Identifier | ForEach-Object { $_.Value }) -join ".")
                )))
        }

        # --------------------------------------------------------------------------- column checking
        $QuerySpecification = @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "QuerySpecification" -IncludeSelf)

        # Scope descent is modelled as containment: a query specification's ancestors are the query
        # specifications that contain it. That is what makes a correlated subquery able to see the
        # outer query's columns - and, deliberately, it also lets a derived table see them, which is
        # more permissive than T-SQL and therefore quieter.
        # Keyed by reference: a ScriptDom node is not a value, and two distinct nodes that happen to
        # describe the same text must never share an entry. The DEFAULT comparer already does that -
        # ScriptDom's fragments inherit Equals and GetHashCode from System.Object - and saying so with
        # ReferenceEqualityComparer would cost the feature its minimum supported runtime, since that
        # type arrived in .NET 5 and this module declares PowerShell 7.0 (.NET Core 3.1).
        $ScopeSource = [System.Collections.Generic.Dictionary[object, object]]::new()
        foreach ($Specification in $QuerySpecification) {
            $ScopeSource[$Specification] = @(Get-SqlQueryScopeSource -QuerySpecification $Specification -SchemaModel $SchemaModel -ScriptDefined $ScriptDefined)
        }

        $Contained = [System.Collections.Generic.Dictionary[object, object]]::new()
        foreach ($Specification in $QuerySpecification) {
            $Contained[$Specification] = [System.Collections.Generic.HashSet[object]]::new(
                [object[]]@(Get-SqlFragmentDescendant -Fragment $Specification -TypeName "QuerySpecification"))
        }

        foreach ($Specification in $QuerySpecification) {
            # Every source visible here: this scope's own, plus those of every scope enclosing it.
            $Visible = [System.Collections.Generic.List[object]]::new()
            foreach ($Candidate in $QuerySpecification) {
                if ([object]::ReferenceEquals($Candidate, $Specification) -or $Contained[$Candidate].Contains($Specification)) {
                    foreach ($Item in $ScopeSource[$Candidate]) {
                        $Visible.Add($Item)
                    }
                }
            }

            if ($Visible.Count -eq 0) {
                # "SELECT 1" and friends. Nothing to resolve against, and a column reference with no
                # FROM clause at all is not this pass's business.
                continue
            }

            if (@($Visible | Where-Object { $_.Opaque }).Count -gt 0) {
                # Issue #61 acceptance criterion 3: one source this pass cannot see through makes
                # every unresolved column in the scope a legitimate possibility, so it says nothing.
                continue
            }

            # Aliases introduced by the SELECT list are referenceable from ORDER BY, and are not
            # columns of any table. Flagging them would make "SELECT x AS y FROM t ORDER BY y" - which
            # is correct T-SQL - a warning.
            $SelectAlias = @{}
            foreach ($Element in @($Specification.SelectElements)) {
                if ($Element.GetType().Name -eq "SelectScalarExpression" -and ![string]::IsNullOrWhiteSpace($Element.ColumnName.Value)) {
                    $SelectAlias[$Element.ColumnName.Value] = $true
                }
            }

            foreach ($Column in @(Get-SqlOwnColumnReference -QuerySpecification $Specification)) {
                if ([string]$Column.ColumnType -ne "Regular") {
                    # A wildcard - "t.*" - names no single column.
                    continue
                }

                $Part = @($Column.MultiPartIdentifier.Identifiers)
                if ($Part.Count -eq 0) {
                    continue
                }

                $ColumnName = [string]$Part[-1].Value
                if ([string]::IsNullOrWhiteSpace($ColumnName)) {
                    continue
                }

                if ($Part.Count -eq 1) {
                    if ($SelectAlias.ContainsKey($ColumnName)) {
                        continue
                    }

                    $Owner = @($Visible | Where-Object { $_.Entry.Column.ContainsKey($ColumnName) })

                    if ($Owner.Count -eq 1) {
                        continue
                    }

                    $Marker = Get-SqlFragmentMarker -Fragment $Column
                    if ($null -eq $Marker) {
                        continue
                    }

                    if ($Owner.Count -eq 0) {
                        $Diagnostic.Add((New-SqlSchemaDiagnosticItem -Marker $Marker -Source $Source -Message (
                                "Column '{0}' is not found in the cached schema on any table in this query. Check the name, or refresh the schema if the database has changed since you connected." -f $ColumnName
                            )))
                    }
                    else {
                        $Diagnostic.Add((New-SqlSchemaDiagnosticItem -Marker $Marker -Source $Source -Message (
                                "Column '{0}' is ambiguous: {1} tables in this query have a column with that name. Qualify it with a table name or alias." -f $ColumnName, $Owner.Count
                            )))
                    }

                    continue
                }

                # Qualified. The part in front of the column names either an alias or a table.
                $Qualifier = [string]$Part[-2].Value
                $Owner = @($Visible | Where-Object { $_.Name -eq $Qualifier })

                if ($Owner.Count -eq 0) {
                    # A qualifier this pass cannot place - a variable, or a scope it does not model -
                    # is not evidence of anything.
                    continue
                }

                if (@($Owner | Where-Object { $_.Entry.Column.ContainsKey($ColumnName) }).Count -gt 0) {
                    continue
                }

                $Marker = Get-SqlFragmentMarker -Fragment $Column
                if ($null -eq $Marker) {
                    continue
                }

                $Diagnostic.Add((New-SqlSchemaDiagnosticItem -Marker $Marker -Source $Source -Message (
                        "Column '{0}' is not found in the cached schema on '{1}'. Check the name, or refresh the schema if the database has changed since you connected." -f $ColumnName, ("{0}.{1}" -f $Owner[0].Entry.Schema, $Owner[0].Entry.Table)
                    )))
            }
        }

        # Count only (issue #61 section 5).
        "Resolved the script against the cached schema: {0} schema diagnostic(s)." -f $Diagnostic.Count | Write-LogOutput -LogType DEBUG

        return @($Diagnostic | Sort-Object -Property @{ Expression = { [int]$_.Line } }, @{ Expression = { [int]$_.Column } })
    }
    catch {
        # A resolver that throws must be no worse than one that is switched off. The message can quote
        # identifiers from the script, so it is not logged.
        "Resolving the query against the cached schema failed; schema diagnostics are unavailable for this run." | Write-LogOutput -LogType DEBUG
        return @()
    }
}

function New-SqlSchemaDiagnosticItem {
    <#
    .SYNOPSIS
        Builds one schema-pass diagnostic in the shared marker shape.

    .DESCRIPTION
        The shape is the contract described in issue #61 section 3 - the same one
        Get-SqlSyntaxDiagnostic emits - so the editor, Move-SqlDiagnosticToSelection and
        ConvertTo-EditorDiagnosticScript need no knowledge of which pass produced a marker. Number is
        0 because a schema miss has no SQL Server error number; the field is kept so the shape does
        not vary between passes.

    .PARAMETER Marker
        The position from Get-SqlFragmentMarker.

    .PARAMETER Message
        The text shown in the editor's hover.

    .PARAMETER Source
        The pass label shown next to the message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Marker,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    return [PSCustomObject][Ordered]@{
        Line      = [int]$Marker.Line
        Column    = [int]$Marker.Column
        EndLine   = [int]$Marker.EndLine
        EndColumn = [int]$Marker.EndColumn
        Severity  = "Warning"
        Message   = $Message
        Source    = $Source
        Number    = 0
    }
}

function Get-SqlSchemaObjectBaseName {
    <#
    .SYNOPSIS
        Returns the last identifier of a ScriptDom SchemaObjectName, or $null.

    .PARAMETER SchemaObject
        The SchemaObjectName to read. Null yields $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $SchemaObject
    )

    if ($null -eq $SchemaObject) {
        return $null
    }

    $Identifier = @($SchemaObject.Identifiers)
    if ($Identifier.Count -eq 0) {
        return $null
    }

    return [string]$Identifier[-1].Value
}

function Resolve-SqlSchemaTable {
    <#
    .SYNOPSIS
        Resolves a one- or two-part table name against the indexed schema.

    .DESCRIPTION
        A two-part name resolves in its own schema or not at all. A one-part name resolves when
        exactly one schema owns it, or - matching SQL Server's usual default and the editor's own
        resolveTableRef - when dbo owns it among several.

        A bare name owned by several non-dbo schemas is AMBIGUOUS, and the two callers need different
        answers about it. The table check only asks whether the object is known, and "known in some
        schema" is a true answer. The column check would have to pick one of them, and picking
        arbitrarily means the columns it then validates against may belong to the wrong table - a
        warning that is wrong in both directions. So the ambiguity is signalled TO THE CALLER through
        the optional -Ambiguous reference, and Get-SqlQueryScopeSource acts on it by treating such a
        source as opaque and skipping its column checks.

        Nothing about the ambiguity reaches the user. It is a reason for this pass to say LESS, not
        something to tell them about: a bare name their query resolves perfectly well at the server is
        not a defect, and warning about it would be the pass complaining about its own limits.

    .PARAMETER SchemaModel
        The indexed schema from Get-SqlSchemaModel.

    .PARAMETER Identifier
        The name's identifiers, in order.

    .PARAMETER Ambiguous
        Set to $true when a one-part name was owned by several schemas and none of them is dbo.

    .OUTPUTS
        The schema model's table entry, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $SchemaModel,
        [Parameter(Mandatory = $true)]
        $Identifier,
        [Parameter(Mandatory = $false)]
        [ref]$Ambiguous
    )

    if ($null -ne $Ambiguous) {
        $Ambiguous.Value = $false
    }

    $Part = @($Identifier)
    $BaseName = [string]$Part[-1].Value

    if ($Part.Count -ge 2) {
        $SchemaName = [string]$Part[-2].Value
        if ([string]::IsNullOrWhiteSpace($SchemaName) -or -not $SchemaModel.BySchema.ContainsKey($SchemaName)) {
            return $null
        }

        $Table = $SchemaModel.BySchema[$SchemaName]
        if ($Table.ContainsKey($BaseName)) {
            return $Table[$BaseName]
        }

        return $null
    }

    if (-not $SchemaModel.ByTableName.ContainsKey($BaseName)) {
        return $null
    }

    $Candidate = @($SchemaModel.ByTableName[$BaseName])
    if ($Candidate.Count -eq 1) {
        return $Candidate[0]
    }

    $Dbo = @($Candidate | Where-Object { $_.Schema -eq "dbo" })
    if ($Dbo.Count -eq 1) {
        return $Dbo[0]
    }

    # Several non-dbo schemas own this name. The entry returned is one of them, which is enough to
    # answer "is this object known?" and not enough to answer "what are its columns?".
    if ($null -ne $Ambiguous) {
        $Ambiguous.Value = $true
    }

    return $Candidate[0]
}

function Get-SqlTableReferenceLeaf {
    <#
    .SYNOPSIS
        Flattens a ScriptDom table reference into the individual sources it contributes to a FROM
        clause.

    .DESCRIPTION
        Only joins are unwrapped. Everything else - a derived table, PIVOT, OPENJSON, a table-valued
        function, a table variable - is a leaf, because its columns are exactly what this pass cannot
        see through and what therefore has to be reported as one opaque source rather than as the
        table hiding inside it. Unwrapping PIVOT, in particular, would hand the scope the columns of
        the table being pivoted, which are not the columns the query can then name.

    .PARAMETER TableReference
        The reference to flatten.

    .OUTPUTS
        The leaf table references.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $TableReference
    )

    if ($null -eq $TableReference) {
        return @()
    }

    switch ($TableReference.GetType().Name) {
        { $_ -in @("QualifiedJoin", "UnqualifiedJoin") } {
            return @(
                @(Get-SqlTableReferenceLeaf -TableReference $TableReference.FirstTableReference) +
                @(Get-SqlTableReferenceLeaf -TableReference $TableReference.SecondTableReference)
            )
        }
        "JoinParenthesisTableReference" {
            return @(Get-SqlTableReferenceLeaf -TableReference $TableReference.TableReference)
        }
        default {
            return @($TableReference)
        }
    }
}

function Get-SqlQueryScopeSource {
    <#
    .SYNOPSIS
        Describes the FROM sources of one query specification: what each one is called, what it
        resolved to, and whether this pass can see its columns.

    .PARAMETER QuerySpecification
        The scope to describe.

    .PARAMETER SchemaModel
        The indexed schema from Get-SqlSchemaModel.

    .PARAMETER ScriptDefined
        Names the script defines itself, which never resolve against the database.

    .OUTPUTS
        [PSCustomObject] per source, with Name (alias, else table name), Entry (the schema model's
        table entry, or $null) and Opaque (whether its columns are unknown).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QuerySpecification,
        [Parameter(Mandatory = $true)]
        $SchemaModel,
        [Parameter(Mandatory = $true)]
        $ScriptDefined
    )

    $Source = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($null -eq $QuerySpecification.FromClause) {
        return @($Source)
    }

    foreach ($Reference in @($QuerySpecification.FromClause.TableReferences)) {
        foreach ($Leaf in @(Get-SqlTableReferenceLeaf -TableReference $Reference)) {
            $Alias = [string]$Leaf.Alias.Value

            if ($Leaf.GetType().Name -ne "NamedTableReference") {
                $Source.Add([PSCustomObject]@{ Name = $Alias; Entry = $null; Opaque = $true })
                continue
            }

            $Identifier = @($Leaf.SchemaObject.Identifiers)
            $BaseName = if ($Identifier.Count -gt 0) { [string]$Identifier[-1].Value } else { "" }
            $Name = if (![string]::IsNullOrWhiteSpace($Alias)) { $Alias } else { $BaseName }

            $IsScriptDefined = $Identifier.Count -eq 1 -and $ScriptDefined.ContainsKey($BaseName)
            $IsTemporary = $BaseName.StartsWith("#") -or $BaseName.StartsWith("@")

            if ($IsScriptDefined -or $IsTemporary -or $Identifier.Count -ge 3) {
                $Source.Add([PSCustomObject]@{ Name = $Name; Entry = $null; Opaque = $true })
                continue
            }

            $IsAmbiguous = $false
            $Entry = Resolve-SqlSchemaTable -SchemaModel $SchemaModel -Identifier $Identifier -Ambiguous ([ref]$IsAmbiguous)

            if ($null -eq $Entry) {
                # The table itself is already reported by the table pass. Marking the source opaque
                # stops the same mistake being reported a second time, once per column.
                $Source.Add([PSCustomObject]@{ Name = $Name; Entry = $null; Opaque = $true })
                continue
            }

            if ($IsAmbiguous) {
                # A bare name owned by several non-dbo schemas. Which one the query means is not
                # knowable from the text, so validating columns against the arbitrary pick would be a
                # guess - and a guess that can be wrong in both directions. Opaque instead.
                $Source.Add([PSCustomObject]@{ Name = $Name; Entry = $null; Opaque = $true })
                continue
            }

            $Source.Add([PSCustomObject]@{ Name = $Name; Entry = $Entry; Opaque = $false })
        }
    }

    return @($Source)
}

function Get-SqlOwnColumnReference {
    <#
    .SYNOPSIS
        Returns the column references that belong to one query specification rather than to a query
        nested inside it.

    .DESCRIPTION
        A column in a subquery is resolved in the subquery's own scope, so it must not also be
        resolved in the enclosing one - where its table may not be in the FROM clause at all. The
        subtraction is by reference, which is the only identity a ScriptDom node has.

    .PARAMETER QuerySpecification
        The scope whose own column references are wanted.

    .OUTPUTS
        The ColumnReferenceExpression nodes belonging directly to this scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QuerySpecification
    )

    $Nested = [System.Collections.Generic.HashSet[object]]::new()

    foreach ($Inner in @(Get-SqlFragmentDescendant -Fragment $QuerySpecification -TypeName "QuerySpecification")) {
        foreach ($Column in @(Get-SqlFragmentDescendant -Fragment $Inner -TypeName "ColumnReferenceExpression" -IncludeSelf)) {
            [void]$Nested.Add($Column)
        }
    }

    return @(Get-SqlFragmentDescendant -Fragment $QuerySpecification -TypeName "ColumnReferenceExpression" |
            Where-Object { -not $Nested.Contains($_) })
}
