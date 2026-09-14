function Get-DataGridSelectionSchema {
    <#
    .SYNOPSIS
        Resolves the selected DataGrid columns to the property names and types the clipboard
        formatters need.

    .DESCRIPTION
        The only part of the #103 copy path that reads the grid, so everything downstream of it is
        testable without a UI.

        Two things it gets right that the pre-#103 code did not:

          * It carries the BINDING PATH, not the header. Headers pass through Invoke-SanitizeJsonKeys
            and the grid's own header escaping, so a header is not reliably the name of the property
            it displays. SortMemberPath is what AutoGenerateColumns sets from the property itself.
          * It leaves the value alone. OnCopyingCellClipboardContent renders a cell to text, and
            rendering to text under the thread culture is what discards the type information this
            whole change exists to keep.

        SqlType is priority 1 of the issue's resolution order - the declared type from the cached
        SQL schema. PR #106 left it as a seam that nothing filled, which is what issue #120 found:
        against a tenant whose response types every column as a string, the CLR type of the value is
        no evidence at all, so the whole feature reduced to quoting everything. The lookup now lives
        in Get-QueryColumnSqlTypeMap and this is where its answer meets the grid.

        A column that does not resolve keeps SqlType $null and is typed the way it was before. That
        is the normal case for an expression or an alias, and it is by design: the map answers only
        where it is certain.

    .PARAMETER DataGrid
        The DataGrid to read. Defaults to the query result grid.

    .PARAMETER SqlTypeMap
        Column name -> declared SQL type, as built by Get-QueryColumnSqlTypeMap. Omit it and the map
        for the query behind the current result is resolved here; pass one to resolve against a
        given schema, which is what keeps the decision testable without an application.

    .OUTPUTS
        [PSCustomObject[]] one entry per selected column, in display order, with Header,
        PropertyName, SqlType and AllowValuePromotion.

    .EXAMPLE
        $ColumnSchema = Get-DataGridSelectionSchema

    .NOTES
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        $DataGrid,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$SqlTypeMap
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, "<suppressed: carries grid content>"))

    # ContainsKey, not a $null test: an OMITTED -DataGrid means "the query result grid", while an
    # explicitly passed $null means "no grid" and must not silently resolve to a different one. The
    # two are indistinguishable from the parameter's value alone.
    if (-not $PSBoundParameters.ContainsKey("DataGrid")) {
        $DataGrid = $Script:MainForm.Elements.DataGridQueryResult
    }

    if ($null -eq $DataGrid -or $null -eq $DataGrid.SelectedCells -or $DataGrid.SelectedCells.Count -le 0) {
        return @()
    }

    # ContainsKey again, for the same reason: an explicit $null map means "resolve nothing", which
    # is not the same request as leaving the parameter off.
    if (-not $PSBoundParameters.ContainsKey("SqlTypeMap")) {
        # Nothing about resolving a declared type may cost the user their copy: no types is the
        # state every copy was in before issue #120, and it still produces correct output.
        try {
            $SqlTypeMap = Get-ActiveQueryColumnSqlTypeMap
        }
        catch {
            $SqlTypeMap = @{}
        }
    }

    if ($null -eq $SqlTypeMap) {
        $SqlTypeMap = @{}
    }

    # Asked of the whole bound result set rather than of the selection: a single text column looks
    # the same in a typed response and an untyped one, and only the rest of the payload tells them
    # apart. See Test-QueryResultRowIsUntyped.
    $AllowValuePromotion = $false
    try {
        $AllowValuePromotion = Test-QueryResultRowIsUntyped -Row $DataGrid.Items
    }
    catch {
        $AllowValuePromotion = $false
    }

    $SelectedColumnSet = [System.Collections.Generic.HashSet[object]]::new()
    $SelectedColumns = [System.Collections.Generic.List[object]]::new()
    foreach ($SelectedCell in $DataGrid.SelectedCells) {
        if ($SelectedColumnSet.Add($SelectedCell.Column)) {
            $SelectedColumns.Add($SelectedCell.Column)
        }
    }

    $ColumnSchema = [System.Collections.Generic.List[object]]::new()
    foreach ($Column in @($SelectedColumns | Sort-Object -Property DisplayIndex)) {
        $Header = "{0}" -f $Column.Header

        # SortMemberPath first, header second. The fallback matters for a column that was not
        # autogenerated and therefore has no binding path; for those the header is all there is.
        $PropertyName = $Column.SortMemberPath
        if ([string]::IsNullOrWhiteSpace($PropertyName)) {
            $PropertyName = $Header
        }

        # The BINDING PATH is what the map is keyed by, and the header is only a fallback for it.
        # A header has been through Invoke-SanitizeJsonKeys and the grid's header escaping, so it is
        # not reliably the name of anything in the query.
        $SqlType = $null
        if ($SqlTypeMap.ContainsKey($PropertyName)) {
            $SqlType = [string]$SqlTypeMap[$PropertyName]
        }

        $ColumnSchema.Add([PSCustomObject]@{
                Header              = $Header
                PropertyName        = $PropertyName
                SqlType             = $SqlType
                AllowValuePromotion = $AllowValuePromotion
            })
    }

    return @($ColumnSchema)
}
