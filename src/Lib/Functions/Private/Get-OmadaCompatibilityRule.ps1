function Get-OmadaCompatibilityRule {
    <#
    .SYNOPSIS
        The catalogue of Omada-specific compatibility rules - the third validation pass of issue #61.

    .DESCRIPTION
        Issue #61 section 3.4 asks for a catalogue rather than a walker full of ifs, and this is it.
        There WILL be more Omada quirks, and each one must cost a table entry and a test, not a
        rewrite. So a rule is data:

            Id          the "OMDnnn" identifier, which the configuration, the editor and the tests
                        all use to address it
            Number      the numeric part of the id, carried on every diagnostic so a marker can be
                        traced back to its rule without parsing a string
            Title       a short name, for the configuration UI and for the tests
            Severity    the default severity, overridable per rule from configuration
            Find        a predicate over the parsed script, returning the fragments to mark and the
                        message for each

        Find receives a context object with the parsed script and the statement and result-scope
        lists the rules share, so a rule that needs "every top-level result column" does not have to
        work out what that means for itself.

        WHAT IS AND IS NOT IN THIS TABLE. Only the rules issue #61 section 3.2 marks as claimed are
        here: OMD001, OMD003, OMD004 and OMD010-OMD013. Every rule marked *Candidate* there -
        OMD002, OMD005, OMD006, OMD007, OMD014, OMD015 and OMD016 - needs a captured tenant response
        before it earns a severity, and none has one yet. A rule with no fixture is a guess, and a
        guessing rule is how a validation pass gets switched off.

        NOTHING HERE PREVENTS ANYTHING. The execution-model rules describe the tool's read-only
        posture (section 3.10); the tenant's permission set is what enforces it. These rules explain
        the boundary at the moment the user meets it, and the user can always overrule them.

    .OUTPUTS
        The rule definitions, in id order.
    #>
    [CmdletBinding()]
    param()

    # No tracer preamble: this is on the debounced validation path (issue #61 section 5).

    return @(
        [PSCustomObject][Ordered]@{
            Id       = "OMD001"
            Number   = 1
            Title    = "Result column has no name"
            Severity = "Warning"
            Find     = {
                param($Context)

                foreach ($Specification in $Context.ResultQuerySpecification) {
                    foreach ($Element in @($Specification.SelectElements)) {
                        if (-not (Test-SqlSelectElementNameless -SelectElement $Element)) {
                            continue
                        }

                        [PSCustomObject]@{
                            Fragment    = $Element
                            KeywordOnly = $false
                            Message     = "This column has no name. Omada returns no rows for a result set containing an unnamed column - the query runs, but the result arrives empty. Add an alias, for example AS [{0}]." -f (Get-SqlSuggestedColumnAlias -Expression $Element.Expression)
                        }
                    }
                }
            }
        }

        [PSCustomObject][Ordered]@{
            Id       = "OMD003"
            Number   = 3
            Title    = "Alias is renamed in the result grid"
            Severity = "Info"
            Find     = {
                param($Context)

                foreach ($Specification in $Context.ResultQuerySpecification) {
                    foreach ($Element in @($Specification.SelectElements)) {
                        if ($Element.GetType().Name -ne "SelectScalarExpression") {
                            continue
                        }

                        $Alias = [string]$Element.ColumnName.Value
                        if ([string]::IsNullOrEmpty($Alias) -or $Alias -notmatch '[^A-Za-z0-9_\-]') {
                            continue
                        }

                        [PSCustomObject]@{
                            Fragment    = $Element.ColumnName
                            KeywordOnly = $false
                            Message     = "The alias '{0}' contains characters the result grid cannot keep. Every character outside A-Z, a-z, 0-9, _ and - is replaced with an underscore, so the column appears under a different name than the one written here." -f $Alias
                        }
                    }
                }
            }
        }

        [PSCustomObject][Ordered]@{
            Id       = "OMD004"
            Number   = 4
            Title    = "Nameless column in a derived table, CTE or SELECT INTO"
            Severity = "Error"
            Find     = {
                param($Context)

                foreach ($Scope in $Context.NamedScope) {
                    foreach ($Element in @($Scope.QuerySpecification.SelectElements)) {
                        if (-not (Test-SqlSelectElementNameless -SelectElement $Element)) {
                            continue
                        }

                        [PSCustomObject]@{
                            Fragment    = $Element
                            KeywordOnly = $false
                            Message     = "This column has no name, and SQL Server requires one here: a column in a {0} must be named (Msg 8155). The server rejects the batch, which reaches this tool as an opaque reference number. Add an alias, for example AS [{1}]." -f $Scope.Description, (Get-SqlSuggestedColumnAlias -Expression $Element.Expression)
                        }
                    }
                }
            }
        }

        [PSCustomObject][Ordered]@{
            Id       = "OMD010"
            Number   = 10
            Title    = "Data manipulation is not available"
            Severity = "Error"
            Find     = {
                param($Context)

                $Keyword = @{
                    InsertStatement        = "INSERT"
                    UpdateStatement        = "UPDATE"
                    DeleteStatement        = "DELETE"
                    MergeStatement         = "MERGE"
                    TruncateTableStatement = "TRUNCATE TABLE"
                }

                foreach ($Statement in $Context.Statement) {
                    $Name = $Statement.GetType().Name
                    if (-not $Keyword.ContainsKey($Name)) {
                        continue
                    }

                    [PSCustomObject]@{
                        Fragment    = $Statement
                        KeywordOnly = $true
                        Message     = "The SQL Troubleshooter has read access only. {0} cannot run here - use a SELECT to inspect the data." -f $Keyword[$Name]
                    }
                }
            }
        }

        [PSCustomObject][Ordered]@{
            Id       = "OMD011"
            Number   = 11
            Title    = "Data definition is not available"
            Severity = "Error"
            Find     = {
                param($Context)

                foreach ($Statement in $Context.Statement) {
                    # Matched on the statement's kind, never on the text: issue #61 acceptance
                    # criterion A15 requires that a SELECT mentioning "create" in a literal or an
                    # alias raises nothing. ScriptDom names every DDL statement Create*, Alter* or
                    # Drop*, which is the whole of the family.
                    if ($Statement.GetType().Name -notmatch '^(Create|Alter|Drop)\w*Statement$') {
                        continue
                    }

                    [PSCustomObject]@{
                        Fragment    = $Statement
                        KeywordOnly = $true
                        Message     = "The SQL Troubleshooter has read access only. Creating, altering or dropping database objects cannot run here - use a SELECT to inspect the data."
                    }
                }
            }
        }

        [PSCustomObject][Ordered]@{
            Id       = "OMD012"
            Number   = 12
            Title    = "Stored procedures and dynamic SQL are not available"
            Severity = "Error"
            Find     = {
                param($Context)

                foreach ($Statement in $Context.Statement) {
                    if ($Statement.GetType().Name -ne "ExecuteStatement") {
                        continue
                    }

                    [PSCustomObject]@{
                        Fragment    = $Statement
                        KeywordOnly = $true
                        Message     = "Stored procedures cannot be executed from the SQL Troubleshooter. Only a single SELECT statement runs here, so EXEC, EXECUTE and sp_executesql are all unavailable."
                    }
                }
            }
        }

        [PSCustomObject][Ordered]@{
            Id       = "OMD013"
            Number   = 13
            Title    = "Temporary tables are not available"
            Severity = "Error"
            Find     = {
                param($Context)

                $Message = "Temporary tables are not available. Use a common table expression (WITH ... AS (...)) instead - CTEs are supported."

                foreach ($Reference in @(Get-SqlFragmentDescendant -Fragment $Context.Fragment -TypeName "NamedTableReference")) {
                    $Name = Get-SqlSchemaObjectBaseName -SchemaObject $Reference.SchemaObject
                    if ([string]::IsNullOrWhiteSpace($Name) -or -not $Name.StartsWith("#")) {
                        continue
                    }

                    [PSCustomObject]@{
                        Fragment    = $Reference.SchemaObject
                        KeywordOnly = $false
                        Message     = $Message
                    }
                }

                foreach ($Statement in $Context.Statement) {
                    $Target = $null
                    switch ($Statement.GetType().Name) {
                        "SelectStatement" { $Target = $Statement.Into }
                        "CreateTableStatement" { $Target = $Statement.SchemaObjectName }
                    }

                    $Name = Get-SqlSchemaObjectBaseName -SchemaObject $Target
                    if ([string]::IsNullOrWhiteSpace($Name) -or -not $Name.StartsWith("#")) {
                        continue
                    }

                    [PSCustomObject]@{
                        Fragment    = $Target
                        KeywordOnly = $false
                        Message     = $Message
                    }
                }
            }
        }
    )
}

function Test-SqlSelectElementNameless {
    <#
    .SYNOPSIS
        Decides whether a SELECT element produces a result column with no name.

    .DESCRIPTION
        The detection rule of issue #61 section 3.3, in one place because OMD001 and OMD004 ask the
        same question about different scopes.

        A scalar expression is nameless when it carries no alias AND is not a bare column reference -
        a column reference is named by the column. COUNT(*), a literal, an arithmetic expression, a
        CASE, a CONVERT, an ISNULL and a scalar subquery are not.

        SelectStarExpression is skipped: its names come from the schema, which is OMD002's territory
        and is still a candidate rule. SelectSetVariable is not a result column at all.

    .PARAMETER SelectElement
        The element to examine.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $SelectElement
    )

    if ($null -eq $SelectElement -or $SelectElement.GetType().Name -ne "SelectScalarExpression") {
        return $false
    }

    if (![string]::IsNullOrEmpty([string]$SelectElement.ColumnName.Value)) {
        return $false
    }

    if ($null -eq $SelectElement.Expression) {
        return $false
    }

    return ($SelectElement.Expression.GetType().Name -ne "ColumnReferenceExpression")
}

function Get-SqlSuggestedColumnAlias {
    <#
    .SYNOPSIS
        Suggests an alias for a nameless result column, for the text of the OMD001 and OMD004
        messages.

    .DESCRIPTION
        The suggestion is derived from the expression, as issue #61 section 3.3 asks: a function call
        suggests the function's name, a literal suggests Value, and anything else falls back to
        Column. It is a hint in a message, never an edit - the query text is the user's.

    .PARAMETER Expression
        The nameless expression.

    .OUTPUTS
        [string] a suggestion made only of characters the result grid keeps.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Expression
    )

    if ($null -eq $Expression) {
        return "Column"
    }

    # Every branch breaks: without it a type name matching two patterns would make the switch emit
    # two values, and the "suggestion" would be an array.
    $Suggestion = switch -Regex ($Expression.GetType().Name) {
        '^FunctionCall$' { [string]$Expression.FunctionName.Value; break }
        'Literal$' { "Value"; break }
        'CaseExpression$' { "Case"; break }
        '^(Convert|Cast)Call$' { "Value"; break }
        '^ScalarSubquery$' { "Value"; break }
        default { "Column" }
    }

    if ([string]::IsNullOrWhiteSpace($Suggestion)) {
        $Suggestion = "Column"
    }

    # The suggestion goes into a message that tells the user their alias would otherwise be renamed,
    # so it must not itself be a name that gets renamed (OMD003).
    return ($Suggestion -replace '[^A-Za-z0-9_\-]', '_')
}
