function Get-SqlDatabaseReference {
    <#
    .SYNOPSIS
        Finds every database a script addresses explicitly - by a database-qualified object name or
        by USE - and reports the forms that cannot be executed.

    .DESCRIPTION
        Omada's SqlDataProducer runs the stored query text against the one data connection attached
        to the query data object, so a three-part name is a SQL error on the server. Issue #152
        resolves the database client-side instead: this function is the read half of that, and
        ConvertTo-UnqualifiedSqlQuery is the write half.

        The scan is done over the ScriptDom tree that already ships with the module (issue #61 /
        #74), not over a hand-written tokenizer. ScriptDom's lexer is what makes the awkward cases
        correct rather than approximated:

        - the three accepted forms ([Db].[Schema].[Table], Db.Schema.Table and the two-dot
          [Db]..[Table]) are all one SchemaObjectName with a DatabaseIdentifier, in any mix of
          bracketed and bare identifiers;
        - identifiers compare case-insensitively, as T-SQL does;
        - a database-qualified name inside a string literal or a comment produces no
          SchemaObjectName at all, so it can never be mistaken for a reference (#152 criterion 15);
        - a four-part linked-server name is simply a SchemaObjectName that also has a
          ServerIdentifier (#152 criterion 10).

        WHY THE WHOLE SCRIPT MUST NAME AT MOST ONE DATABASE. Criterion 8 asks for a *statement* that
        references two databases to be rejected. The posted text is executed as ONE query against ONE
        connection, so two statements each naming a different database is exactly as unrunnable as
        one statement doing it - and so is a USE that disagrees with a prefix elsewhere in the same
        text. All three are rejected as CrossDatabase, and the message names the databases involved.

        A script that does not parse cleanly still yields whatever ScriptDom recovered, exactly as
        Get-SqlScriptFragment describes. Callers get Status Unavailable only when ScriptDom is not
        loaded at all, in which case no database handling happens and execution proceeds as it did
        before the feature existed.

    .PARAMETER SqlText
        The script to scan. Null, empty and whitespace-only input are valid and yield Status Ok with
        nothing found.

    .PARAMETER ParserVersion
        An explicit TSqlNNNParser to use. Omit to take the newest parser the loaded assembly ships.

    .OUTPUTS
        [PSCustomObject] with

            Status        Ok          the script was scanned
                          Unavailable ScriptDom is not loaded, so nothing was scanned
            Database      the distinct database names the script addresses, as written
            UseDatabase   the database named by the last USE statement, or $null
            Rejection     $null, or "CrossDatabase" / "FourPartName"
            Message       the explanation to show the user when Rejection is set, else $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ParserVersion
    )

    # DELIBERATELY no $Script:Tracer preamble and no logging of the text. $PSBoundParameters IS the
    # user's query here, and this runs on every execution (issue #61 section 5).

    $Result = [PSCustomObject]@{
        Status      = "Ok"
        Database    = @()
        UseDatabase = $null
        Rejection   = $null
        Message     = $null
    }

    $Parsed = Get-SqlScriptFragment -SqlText $SqlText -ParserVersion $ParserVersion
    if ($Parsed.Status -ne "Ok") {
        $Result.Status = "Unavailable"
        return $Result
    }

    if ($null -eq $Parsed.Fragment) {
        return $Result
    }

    # Ordered by first appearance, de-duplicated case-insensitively: the message a rejection produces
    # reads better when it names the databases in the order the user wrote them.
    $Name = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Object in @(Get-SqlFragmentDescendant -Fragment $Parsed.Fragment -TypeName "SchemaObjectName" -IncludeSelf)) {
        if ($null -ne $Object.ServerIdentifier -and ![string]::IsNullOrEmpty($Object.ServerIdentifier.Value)) {
            $Result.Rejection = "FourPartName"
            $Result.Message = "Four-part (linked server) names are not supported: the query is executed against a single Omada data connection, which cannot reach another server. Remove the server prefix and run the query against that server's own data connection."
            return $Result
        }

        if ($null -ne $Object.DatabaseIdentifier -and ![string]::IsNullOrEmpty($Object.DatabaseIdentifier.Value)) {
            if ($Seen.Add($Object.DatabaseIdentifier.Value)) {
                $Name.Add($Object.DatabaseIdentifier.Value)
            }
        }
    }

    foreach ($Use in @(Get-SqlFragmentDescendant -Fragment $Parsed.Fragment -TypeName "UseStatement" -IncludeSelf)) {
        if ($null -eq $Use.DatabaseName -or [string]::IsNullOrEmpty($Use.DatabaseName.Value)) {
            continue
        }

        # The LAST USE wins, exactly as it does in SSMS: each one replaces the current database, and
        # the one still in force when the script ends is the one that sticks.
        $Result.UseDatabase = $Use.DatabaseName.Value
        if ($Seen.Add($Use.DatabaseName.Value)) {
            $Name.Add($Use.DatabaseName.Value)
        }
    }

    $Result.Database = @($Name)

    if ($Name.Count -gt 1) {
        $Result.Rejection = "CrossDatabase"
        $Result.Message = "The query addresses more than one database ({0}). Omada executes a query against a single data connection, so a cross-database query cannot run. Split it into one query per database." -f ($Name -join ", ")
    }

    return $Result
}
