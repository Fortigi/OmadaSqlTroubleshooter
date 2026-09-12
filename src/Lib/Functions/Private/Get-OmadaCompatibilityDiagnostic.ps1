function Get-OmadaCompatibilityDiagnostic {
    <#
    .SYNOPSIS
        Runs the Omada compatibility rule catalogue over a parsed script and returns the diagnostics
        it produced.

    .DESCRIPTION
        The third validation pass of issue #61 (addendum, section 3). It exists because some queries
        are valid T-SQL, valid against the schema, and still wrong here: the result comes back as JSON
        objects keyed by column name, so a column with no name has no key and the grid arrives empty
        with the misleading "Query did not return any results!". And the tool reads; it does not
        write, so a statement that writes cannot succeed whatever SQL Server thinks of it.

        The engine is deliberately thin. It builds the shared context once - the statement list, the
        result scopes, the named scopes - applies the configured severity to each rule, runs the
        rules, and shapes what they return into the same marker every other pass emits. All the
        knowledge lives in Get-OmadaCompatibilityRule, which is what makes issue #61 acceptance
        criterion A9 true: a new rule is a new entry in that table plus its test, and nothing here
        changes.

        A rule that throws is dropped, with a DEBUG line naming only its id. One broken rule must not
        cost the user the other six, and it must never cost them their query.

    .PARAMETER Fragment
        The parsed script from Get-SqlScriptFragment. Null yields no diagnostics.

    .PARAMETER RuleSeverity
        Per-rule severity overrides, as name/value pairs: OMD001 = Error | Warning | Info | Off.
        "Off" disables the rule entirely - it neither warns nor takes part in the execute-time
        confirmation (acceptance criterion A7). An unrecognised value leaves the rule at its default,
        because a typo in a configuration file must not silently switch a rule off.

    .PARAMETER Source
        The value written to each diagnostic's Source field. The default keeps the three passes
        distinguishable on the one shared diagnostics channel.

    .OUTPUTS
        Marker-shaped [PSCustomObject]s with Line, Column, EndLine, EndColumn, Severity, Message,
        Source, Number and RuleId. Number carries the numeric part of the rule id, so the editor, the
        configuration and the tests can all address a rule by it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $RuleSeverity,
        [Parameter(Mandatory = $false)]
        [string]$Source = "Omada compatibility"
    )

    # No tracer preamble: the fragment is the user's query, and the rule messages quote the user's own
    # expressions, so they follow the same rule as parse messages (issue #61 acceptance criterion A10).

    if ($null -eq $Fragment) {
        return @()
    }

    try {
        $Context = [PSCustomObject]@{
            Fragment                 = $Fragment
            Statement                = @(Get-SqlStatementNode -Fragment $Fragment)
            ResultQuerySpecification = @(Get-SqlResultScope -Fragment $Fragment)
            NamedScope               = @(Get-SqlNamedScope -Fragment $Fragment)
        }

        $Diagnostic = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($Rule in @(Get-OmadaCompatibilityRule)) {
            $Severity = Resolve-OmadaCompatibilityRuleSeverity -Rule $Rule -RuleSeverity $RuleSeverity
            if ($Severity -eq "Off") {
                continue
            }

            try {
                foreach ($Hit in @(& $Rule.Find $Context)) {
                    if ($null -eq $Hit -or $null -eq $Hit.Fragment) {
                        continue
                    }

                    $Marker = Get-SqlFragmentMarker -Fragment $Hit.Fragment -KeywordOnly:([bool]$Hit.KeywordOnly)
                    if ($null -eq $Marker) {
                        continue
                    }

                    $Diagnostic.Add([PSCustomObject][Ordered]@{
                            Line      = [int]$Marker.Line
                            Column    = [int]$Marker.Column
                            EndLine   = [int]$Marker.EndLine
                            EndColumn = [int]$Marker.EndColumn
                            Severity  = $Severity
                            Message   = [string]$Hit.Message
                            Source    = $Source
                            Number    = [int]$Rule.Number
                            RuleId    = [string]$Rule.Id
                        })
                }
            }
            catch {
                # The id only. A rule's exception message can quote the script it was looking at.
                "The Omada compatibility rule {0} failed and was skipped for this run." -f $Rule.Id | Write-LogOutput -LogType DEBUG
            }
        }

        # Count only (issue #61 acceptance criterion A10).
        "Applied the Omada compatibility rules: {0} diagnostic(s)." -f $Diagnostic.Count | Write-LogOutput -LogType DEBUG

        return @($Diagnostic | Sort-Object -Property @{ Expression = { [int]$_.Line } }, @{ Expression = { [int]$_.Column } }, @{ Expression = { [int]$_.Number } })
    }
    catch {
        "The Omada compatibility pass could not run for this query." | Write-LogOutput -LogType DEBUG
        return @()
    }
}

function Resolve-OmadaCompatibilityRuleSeverity {
    <#
    .SYNOPSIS
        Returns the severity a rule runs at, taking the configured override into account.

    .PARAMETER Rule
        The rule from Get-OmadaCompatibilityRule.

    .PARAMETER RuleSeverity
        The configured overrides, as an object or hashtable keyed on rule id.

    .OUTPUTS
        [string] "Error", "Warning", "Info" or "Off".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Rule,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $RuleSeverity
    )

    if ($null -eq $RuleSeverity) {
        return [string]$Rule.Severity
    }

    $Override = $null
    try {
        if ($RuleSeverity -is [System.Collections.IDictionary]) {
            if ($RuleSeverity.Contains($Rule.Id)) {
                $Override = [string]$RuleSeverity[$Rule.Id]
            }
        }
        else {
            $Override = [string]$RuleSeverity.$($Rule.Id)
        }
    }
    catch {
        return [string]$Rule.Severity
    }

    if ([string]::IsNullOrWhiteSpace($Override)) {
        return [string]$Rule.Severity
    }

    # An unrecognised value keeps the default. A typo must not be a silent "Off".
    switch ($Override.Trim()) {
        "Error" { return "Error" }
        "Warning" { return "Warning" }
        "Info" { return "Info" }
        "Off" { return "Off" }
        default { return [string]$Rule.Severity }
    }
}

function Get-SqlStatementNode {
    <#
    .SYNOPSIS
        Returns every statement in a parsed script, including those nested inside blocks.

    .DESCRIPTION
        The execution-model rules have to see an UPDATE wherever it is written, including inside an
        IF or a BEGIN ... END. ScriptDom has no single "is a statement" type name to filter on, so the
        set is recognised by what a statement actually is: a fragment that is assignable to
        TSqlStatement.

    .PARAMETER Fragment
        The parsed script.

    .OUTPUTS
        The statement nodes, in document order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment
    )

    if ($null -eq $Fragment) {
        return @()
    }

    $StatementType = [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlStatement]

    return @(Get-SqlFragmentDescendant -Fragment $Fragment -IncludeSelf |
            Where-Object { $StatementType.IsAssignableFrom($_.GetType()) })
}

function Get-SqlResultQuerySpecification {
    <#
    .SYNOPSIS
        Returns the query specification whose SELECT list names the result columns of a query
        expression.

    .DESCRIPTION
        For a UNION, EXCEPT or INTERSECT the result column names come from the FIRST branch (issue #61
        section 3.3), so the descent always takes the first operand. Parenthesised expressions are
        unwrapped.

    .PARAMETER QueryExpression
        The expression to descend.

    .OUTPUTS
        The QuerySpecification, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $QueryExpression
    )

    $Current = $QueryExpression

    # Bounded rather than "until it is a QuerySpecification": an expression shape this does not know
    # how to unwrap must end the descent, not spin.
    for ($Depth = 0; $Depth -lt 64 -and $null -ne $Current; $Depth++) {
        switch ($Current.GetType().Name) {
            "QuerySpecification" { return $Current }
            "BinaryQueryExpression" { $Current = $Current.FirstQueryExpression }
            "QueryParenthesisExpression" { $Current = $Current.QueryExpression }
            default { return $null }
        }
    }

    return $null
}

function Get-SqlResultScope {
    <#
    .SYNOPSIS
        Returns the query specifications whose result actually reaches Omada.

    .DESCRIPTION
        The narrowest and most important definition in the compatibility pass. A nameless column is
        only a problem where the result set is delivered to the client, so only a top-level SELECT
        statement counts - never an INSERT ... SELECT, never a DECLARE @x = (SELECT ...), never an
        IF EXISTS (SELECT 1 ...), and never a subquery in a WHERE clause. Getting this wrong makes the
        pass noise, and noise gets switched off (issue #61 acceptance criterion A5).

        Only statements at the top level of a batch are considered: a SELECT inside an IF block is
        conditional, and the tool submits one statement anyway.

        A SELECT ... INTO is excluded here and handled by OMD004 instead - its result goes to a table,
        not to the client, and SQL Server rejects a nameless column in it outright.

    .PARAMETER Fragment
        The parsed script.

    .OUTPUTS
        The result-producing QuerySpecification nodes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment
    )

    if ($null -eq $Fragment) {
        return @()
    }

    $Scope = [System.Collections.Generic.List[object]]::new()

    foreach ($Batch in @($Fragment.Batches)) {
        foreach ($Statement in @($Batch.Statements)) {
            if ($Statement.GetType().Name -ne "SelectStatement" -or $null -ne $Statement.Into) {
                continue
            }

            $Specification = Get-SqlResultQuerySpecification -QueryExpression $Statement.QueryExpression
            if ($null -ne $Specification) {
                $Scope.Add($Specification)
            }
        }
    }

    return @($Scope)
}

function Get-SqlNamedScope {
    <#
    .SYNOPSIS
        Returns the query specifications where SQL Server itself requires every column to be named,
        with a description of why.

    .DESCRIPTION
        A derived table, a common table expression without an explicit column list, and a
        SELECT ... INTO all have to name every column; SQL Server rejects the batch otherwise
        (Msg 8155), which reaches this tool as an opaque reference number. That makes OMD004 an Error
        rather than a warning: the statement cannot succeed.

        A CTE that declares a column list - WITH c (a, b) AS (...) - names its columns there, so it is
        excluded.

    .PARAMETER Fragment
        The parsed script.

    .OUTPUTS
        [PSCustomObject] per scope, with QuerySpecification and Description.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Fragment
    )

    if ($null -eq $Fragment) {
        return @()
    }

    $Scope = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($Derived in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "QueryDerivedTable")) {
        $Specification = Get-SqlResultQuerySpecification -QueryExpression $Derived.QueryExpression
        if ($null -ne $Specification) {
            $Scope.Add([PSCustomObject]@{ QuerySpecification = $Specification; Description = "derived table" })
        }
    }

    foreach ($Cte in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "CommonTableExpression")) {
        if (@($Cte.Columns).Count -gt 0) {
            continue
        }

        $Specification = Get-SqlResultQuerySpecification -QueryExpression $Cte.QueryExpression
        if ($null -ne $Specification) {
            $Scope.Add([PSCustomObject]@{ QuerySpecification = $Specification; Description = "common table expression" })
        }
    }

    foreach ($Select in @(Get-SqlFragmentDescendant -Fragment $Fragment -TypeName "SelectStatement" -IncludeSelf)) {
        if ($null -eq $Select.Into) {
            continue
        }

        $Specification = Get-SqlResultQuerySpecification -QueryExpression $Select.QueryExpression
        if ($null -ne $Specification) {
            $Scope.Add([PSCustomObject]@{ QuerySpecification = $Specification; Description = "SELECT ... INTO" })
        }
    }

    return @($Scope)
}
