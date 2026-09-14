function Format-QueryResultSelection {
    <#
    .SYNOPSIS
        Turns a selection of query result rows into the SQL or PowerShell array text that goes to
        the clipboard.

    .DESCRIPTION
        The decision-making half of "Copy as SQL array" / "Copy as PowerShell array", split out of
        Copy-DataGridToClipboard by issue #103 so it can be tested without a UI. Copy-
        DataGridToClipboard keeps only cell extraction and the Clipboard::SetText call.

        Types are resolved once per column, not once per selection. That is the whole point of the
        change: the pre-#103 code computed a single "are all these cells integers" boolean across
        every selected cell of every selected column, so one non-numeric cell in one column re-typed
        every integer in the other columns as a string.

        Shape follows the selection, per section 3 of the issue:

          * one column  -> an array literal, as before but correctly typed;
          * two or more -> a row-shaped literal, because a flat array of a two-column selection is
            meaningless however well it is typed. SQL gets a VALUES constructor that can be joined
            to directly; PowerShell gets PSCustomObject rows.

        Nothing here logs a copied value. Copied values are identity data by definition, so the log
        lines carry column names, resolved kinds and counts only.

    .PARAMETER Row
        The selected rows, each a PSCustomObject with one property per selected column. A cell that
        is not individually part of the selection arrives as $null - the same choice
        Get-DataGridSelectedQueryResult documents, because a row constructor has to be rectangular.

    .PARAMETER ColumnSchema
        The resolved column schema from Get-DataGridSelectionSchema: Header, PropertyName and
        SqlType per column, in display order.

    .PARAMETER OutputFormat
        SqlArray or PowerShellArray.

    .PARAMETER Setting
        The resolved settings from Get-ArrayCopySetting.

    .OUTPUTS
        [string] the clipboard text, or an empty string when there is nothing to emit.

    .EXAMPLE
        Format-QueryResultSelection -Row $Rows -ColumnSchema $Schema -OutputFormat "SqlArray" -Setting (Get-ArrayCopySetting)

    .NOTES
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Row,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$ColumnSchema,
        [Parameter(Mandatory = $true)]
        [ValidateSet("SqlArray", "PowerShellArray")]
        [string]$OutputFormat,
        [Parameter(Mandatory = $true)]
        $Setting
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, "<suppressed: carries copied values>"))

    if ($null -eq $Row -or $Row.Count -eq 0 -or $null -eq $ColumnSchema -or $ColumnSchema.Count -eq 0) {
        return ""
    }

    $TypedLiteral = [bool]$Setting.PowerShellTypedLiterals
    $IsMultiColumn = $ColumnSchema.Count -gt 1

    # Resolve every column's kind up front, so a column is formatted the same way from its first row
    # to its last.
    $ColumnKind = @{}
    foreach ($Column in $ColumnSchema) {
        $ColumnKind[$Column.PropertyName] = Get-QueryResultColumnKind -Row $Row -Column $Column
    }

    "Copy as {0}: {1} row(s), column(s): {2}" -f $OutputFormat, $Row.Count, (($ColumnSchema | ForEach-Object { "{0}={1}" -f $_.Header, $ColumnKind[$_.PropertyName] }) -join ", ") | Write-LogOutput -LogType DEBUG

    $NullColumn = [System.Collections.Generic.List[string]]::new()
    $SkipNull = ($Setting.NullHandling -eq "Skip")

    if ($SkipNull -and $IsMultiColumn) {
        # A row constructor cannot be ragged, so Skip has no meaning across several columns. Say so
        # rather than silently emitting something the setting did not ask for.
        "ArrayCopyNullHandling is 'Skip', which does not apply to a multi-column selection: every row needs a value for every column. NULLs are emitted instead." | Write-LogOutput -LogType WARNING -SkipDialog
        $SkipNull = $false
    }

    $Line = [System.Collections.Generic.List[string]]::new()
    $EmittedCount = 0

    if ($IsMultiColumn) {
        foreach ($CurrentRow in $Row) {
            $Literal = [System.Collections.Generic.List[string]]::new()
            foreach ($Column in $ColumnSchema) {
                $Value = $CurrentRow.$($Column.PropertyName)
                if ($null -eq $Value -and !$NullColumn.Contains($Column.Header)) {
                    $NullColumn.Add($Column.Header)
                }

                $Literal.Add((Format-SelectionValue -Value $Value -Kind $ColumnKind[$Column.PropertyName] -SqlType $Column.SqlType -OutputFormat $OutputFormat -TypedLiteral:$TypedLiteral))
            }

            if ($OutputFormat -eq "SqlArray") {
                $Line.Add("    ({0})" -f ($Literal -join ", "))
            }
            else {
                $Pair = for ($Index = 0; $Index -lt $ColumnSchema.Count; $Index++) {
                    "{0} = {1}" -f (Format-PowerShellPropertyName -Name $ColumnSchema[$Index].Header), $Literal[$Index]
                }
                $Line.Add("    [PSCustomObject]@{{ {0} }}" -f ($Pair -join "; "))
            }

            $EmittedCount++
        }
    }
    else {
        $Column = $ColumnSchema[0]
        $Kind = $ColumnKind[$Column.PropertyName]

        foreach ($CurrentRow in $Row) {
            $Value = $CurrentRow.$($Column.PropertyName)

            if ($null -eq $Value) {
                if (!$NullColumn.Contains($Column.Header)) {
                    $NullColumn.Add($Column.Header)
                }

                if ($SkipNull) {
                    continue
                }
            }

            $Line.Add("    {0}" -f (Format-SelectionValue -Value $Value -Kind $Kind -SqlType $Column.SqlType -OutputFormat $OutputFormat -TypedLiteral:$TypedLiteral))
            $EmittedCount++
        }
    }

    if ($Line.Count -eq 0) {
        return ""
    }

    if ($NullColumn.Count -gt 0 -and !$SkipNull) {
        # A copied NULL is always worth saying out loud, but only ONE shape carries the IN-list
        # hazard: a single-column SQL list, which is what gets pasted into an IN clause. A VALUES
        # constructor is joined to, and a PowerShell array is not SQL at all. Naming the wrong
        # hazard is worse than naming none - it teaches the reader to distrust the warning.
        if ($OutputFormat -eq "SqlArray" -and !$IsMultiColumn) {
            "The copied selection contains NULL values in column(s): {0}. 'IN (..., NULL)' silently excludes those rows, and 'NOT IN' with a NULL returns no rows at all." -f ($NullColumn -join ", ") | Write-LogOutput -LogType WARNING -SkipDialog
        }
        else {
            "The copied selection contains NULL values in column(s): {0}." -f ($NullColumn -join ", ") | Write-LogOutput -LogType WARNING -SkipDialog
        }
    }

    if ($Setting.MaxValues -gt 0 -and $EmittedCount -gt $Setting.MaxValues) {
        "The copied selection holds {0} {1}, above the ArrayCopyMaxValues threshold of {2}. A large IN list performs badly and can hit the expression limit (error 8623); consider a temporary table instead." -f $EmittedCount, $(if ($IsMultiColumn) { "rows" } else { "values" }), $Setting.MaxValues | Write-LogOutput -LogType WARNING -SkipDialog
    }

    if ($OutputFormat -eq "SqlArray") {
        if ($IsMultiColumn) {
            $ColumnList = ($ColumnSchema | ForEach-Object { Format-SqlDelimitedIdentifier -Name $_.Header }) -join ", "
            return "(VALUES`r`n{0}`r`n) AS t ({1})" -f (($Line -join ",`r`n")), $ColumnList
        }

        return "(`r`n{0}`r`n)" -f ($Line -join ",`r`n")
    }

    if ($IsMultiColumn) {
        # Newline-separated, not comma-separated: PowerShell takes a newline as the element
        # separator inside @(), and a trailing comma on a PSCustomObject line is easy to lose in a
        # hand edit.
        return "@(`r`n{0}`r`n)" -f ($Line -join "`r`n")
    }

    return "@(`r`n{0}`r`n)" -f ($Line -join ",`r`n")
}

function Get-QueryResultColumnKind {
    <#
    .SYNOPSIS
        Resolves the single literal kind to format every value of one column with.

    .DESCRIPTION
        Resolving per column rather than per value is what stops one row from changing how another
        row of the same column is rendered. The kind is agreed across every non-null value:

          * no non-null values at all -> Null. The column is emitted as NULL throughout.
          * one kind -> that kind.
          * several numeric kinds -> the widest of them. JSON deserialisation is allowed to hand
            back 900 as an Int64 and 12.5 as a Double from the same decimal column, and re-typing
            the whole column as text because of that would be the old bug again.
          * anything else mixed -> String. Quoting a column that cannot be agreed on is always
            safe; picking one of the candidates never is.

        Issue #120 added the two steps that make this work against a response which types every
        column as a string, where the CLR type answers "String" for everything:

          * CORROBORATION. A declared SQL type is a name-based resolution against a cached schema,
            so it is trusted only as far as the values bear it out. Every value in the column has to
            be one the declared kind can actually hold, or the whole column degrades to String. That
            is what makes a wrong schema resolution harmless - and what keeps "007" quoted even in a
            column the schema calls an int.
          * PROMOTION. With no declared type and every value a string, the last remaining source is
            the text. It is used only for a column whose values are ALL canonical numbers (see
            Get-CanonicalNumericStringKind) - one decision for the whole column, never per cell and
            never across columns. One non-numeric value leaves the whole column quoted. And it runs
            only for a response that carried no types at all, which the column schema states in
            AllowValuePromotion: on a typed response a JSON string means the column is textual, and
            promoting there would re-break acceptance criterion 1.

    .PARAMETER Row
        The selected rows.

    .PARAMETER Column
        The column schema entry to resolve.

    .OUTPUTS
        [string] the resolved kind.

    .NOTES
        No tracer preamble: called once per column on the clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyCollection()]
        [object[]]$Row,
        [Parameter(Mandatory = $true)]
        $Column
    )

    $Value = [System.Collections.Generic.List[object]]::new()
    foreach ($CurrentRow in $Row) {
        $CurrentValue = $CurrentRow.$($Column.PropertyName)
        if ($null -eq $CurrentValue -or $CurrentValue -is [System.DBNull]) {
            continue
        }

        $Value.Add($CurrentValue)
    }

    if ($Value.Count -eq 0) {
        return "Null"
    }

    # Priority 1, and the corroboration that keeps it honest.
    $DeclaredKind = Get-SqlTypeNameKind -SqlType $Column.SqlType
    if (![string]::IsNullOrWhiteSpace($DeclaredKind)) {
        if (@($Value | Where-Object { -not (Test-QueryResultValueFitsKind -Value $_ -Kind $DeclaredKind) }).Count -eq 0) {
            return $DeclaredKind
        }

        # The column name, the two kinds and nothing else: the value that did not fit is the reason
        # this line exists and is exactly what must not be written down.
        "Column '{0}' is declared as {1} but not every value can be emitted as one; the column is copied as text instead." -f $Column.Header, $DeclaredKind | Write-LogOutput -LogType DEBUG
        return "String"
    }

    $Kind = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($CurrentValue in $Value) {
        $Kind.Add((Get-QueryResultValueKind -Value $CurrentValue)) | Out-Null
    }

    $Resolved = "String"
    if ($Kind.Count -eq 1) {
        $Resolved = @($Kind)[0]
    }
    else {
        $Numeric = @("Integer", "Decimal", "Float")
        if (@($Kind | Where-Object { $_ -notin $Numeric }).Count -eq 0) {
            if ($Kind.Contains("Float")) { $Resolved = "Float" }
            elseif ($Kind.Contains("Decimal")) { $Resolved = "Decimal" }
            else { $Resolved = "Integer" }
        }
    }

    if ($Resolved -ne "String") {
        return $Resolved
    }

    # Promotion is the last resort and it only applies to a response that carried NO types at all.
    # On a typed response a string value is evidence in its own right - the endpoint sent a JSON
    # string because the column is textual - and promoting it there would re-break issue #103's
    # acceptance criterion 1. Get-DataGridSelectionSchema decides this from the bound rows, once per
    # copy, and an absent flag means "no" so nothing promotes by accident.
    if ($Column.AllowValuePromotion -ne $true) {
        return "String"
    }

    return (Get-PromotedColumnKind -Value $Value)
}

function Get-PromotedColumnKind {
    <#
    .SYNOPSIS
        Promotes a column of numeric-looking strings to a numeric kind, or leaves it a string.

    .DESCRIPTION
        Priority 3 of issue #103's order, widened by issue #120 for the case #103 did not have to
        handle: a response that carries every column as text. #103 restricted refinement to picking
        a narrower shape INSIDE a string, never promoting one to a number, because unrestricted
        sniffing turns "007" into 7. Against an untyped response that restriction leaves the feature
        with no source at all and it quotes an int column - which is the bug #120 reports.

        The promotion is therefore as narrow as it can be and still fix that:

          * The COLUMN decides, never the cell. Every non-null value must be a string, and every one
            of them must be a canonical number; one value that is not leaves the whole column
            quoted. So a single "IDG-900" keeps its whole column a string, and a column of mixed
            "007" and "8" stays a string because "007" is not canonical.
          * Canonical means the text is the only text that renders that number, so re-emitting it
            unquoted cannot change it. Leading zeros, leading "+", exponents, thousands separators
            and surrounding whitespace all disqualify a value - see
            Get-CanonicalNumericStringKind.
          * It runs ONLY when nothing better answered. A declared SQL type is consulted first and
            wins outright, so a schema that says nvarchar keeps its digits quoted.

    .PARAMETER Value
        Every non-null value of the column.

    .OUTPUTS
        [string] Integer, Decimal, or String when the column cannot be promoted.

    .NOTES
        No tracer preamble: called once per column on the clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyCollection()]
        $Value
    )

    $Promoted = "Integer"

    foreach ($CurrentValue in @($Value)) {
        $BaseValue = $CurrentValue
        if ($null -ne $BaseValue -and $BaseValue.GetType() -eq [System.Management.Automation.PSObject]) {
            $BaseValue = $BaseValue.BaseObject
        }

        if ($BaseValue -isnot [string]) {
            return "String"
        }

        $NumericKind = Get-CanonicalNumericStringKind -Value $BaseValue
        if ([string]::IsNullOrWhiteSpace($NumericKind)) {
            return "String"
        }

        if ($NumericKind -eq "Decimal") {
            $Promoted = "Decimal"
        }
    }

    return $Promoted
}

function Format-SelectionValue {
    <#
    .SYNOPSIS
        Formats one value for the requested output format.

    .DESCRIPTION
        A thin dispatcher over ConvertTo-SqlLiteral and ConvertTo-PowerShellLiteral, so the shape
        code above never has to branch on the output format twice.

    .PARAMETER Value
        The raw value.

    .PARAMETER Kind
        The column's resolved kind.

    .PARAMETER SqlType
        The column's declared SQL type when known.

    .PARAMETER OutputFormat
        SqlArray or PowerShellArray.

    .PARAMETER TypedLiteral
        Emit explicit casts in PowerShell output.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called once per copied cell.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$Kind,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlType,
        [Parameter(Mandatory = $true)]
        [ValidateSet("SqlArray", "PowerShellArray")]
        [string]$OutputFormat,
        [switch]$TypedLiteral
    )

    # A null cell is NULL whatever the column resolved to, so the column kind is not forced onto it.
    $EffectiveKind = if ($null -eq $Value -or $Value -is [System.DBNull]) { "Null" } else { $Kind }

    if ($OutputFormat -eq "SqlArray") {
        return ConvertTo-SqlLiteral -Value $Value -Kind $EffectiveKind -SqlType $SqlType
    }

    return ConvertTo-PowerShellLiteral -Value $Value -Kind $EffectiveKind -SqlType $SqlType -TypedLiteral:$TypedLiteral
}

function Format-SqlDelimitedIdentifier {
    <#
    .SYNOPSIS
        Wraps a name in square brackets as a T-SQL delimited identifier.

    .DESCRIPTION
        Doubling the closing bracket is the escaping rule for a bracketed identifier, and it is the
        reason a column header containing "]" cannot break out of the column list of the generated
        VALUES constructor.

    .PARAMETER Name
        The identifier to delimit.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called once per selected column.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name
    )

    if ($null -eq $Name) {
        $Name = ""
    }

    return "[{0}]" -f ($Name -replace "\]", "]]")
}

function Format-PowerShellPropertyName {
    <#
    .SYNOPSIS
        Renders a column header as a PowerShell hashtable key.

    .DESCRIPTION
        A key that is already a plain identifier is emitted bare, because that is what a hand
        written hashtable looks like. Anything else is quoted and escaped, so a header with a space,
        a quote or a bracket in it still produces a hashtable that parses.

    .PARAMETER Name
        The header to render.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called once per selected column per row.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrEmpty($Name)) {
        return "''"
    }

    if ($Name -match "^[A-Za-z_][A-Za-z0-9_]*$") {
        return $Name
    }

    return "'{0}'" -f ($Name -replace "'", "''")
}
