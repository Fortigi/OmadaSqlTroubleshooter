function Get-QueryResultValueKind {
    <#
    .SYNOPSIS
        Resolves a single query result value to the literal kind that should be emitted for it.

    .DESCRIPTION
        The one place that decides "what is this value, really", so ConvertTo-SqlLiteral and
        ConvertTo-PowerShellLiteral cannot disagree with each other about the same cell.

        Resolution follows the priority order in issue #103:

          1. The declared SQL type of the column, when one is known. Nothing resolves a grid column
             back to a schema column yet - that needs the executed query's aliases and joins parsed
             - so SqlType is always $null today. The parameter exists so that work can be added
             without reshaping either formatter.
          2. The CLR type of the underlying row property. Result rows are ConvertFrom-Json output of
             the SqlDataProducer response, so int arrives as a number, bit as a boolean and NULL as
             $null. This is the working default and it is always available.
          3. Value shape, used ONLY to pick a narrower kind inside a value that is already known to
             be a string. It never promotes a string to a number: that is precisely the bug this
             issue exists to fix, and it is what silently turns the code "007" into 7.

        Refinement under priority 3 is deliberately narrow. It fires for an ISO 8601 timestamp and
        for a GUID, and for nothing else:

          * A time component is required, so a bare "2019-01-01" stays a string. Without a time
            there is no way to tell a date column from a product code that happens to look like a
            date, and guessing wrong rewrites the value.
          * Time-only and numeric-looking strings are never refined, for the same reason.

        Both refinements are safe in the sense that matters: the SQL literal for a refined string is
        still a quoted literal, just canonicalised, so a wrong guess cannot change a string into an
        unquoted one.

    .PARAMETER Value
        The raw value read from the row property. May be $null or [DBNull]::Value.

    .PARAMETER SqlType
        The declared SQL type of the column when it is known, for example "nvarchar(50)" or "bit".
        Reserved for the schema resolution described above; currently always $null.

    .PARAMETER SkipValueRefinement
        Resolve from the CLR type alone and skip priority 3 entirely.

    .OUTPUTS
        [string] one of Null, Integer, Decimal, Float, Boolean, Date, DateTime, DateTimeOffset,
        Time, Guid, Binary, String.

    .EXAMPLE
        Get-QueryResultValueKind -Value 900
        Integer

    .EXAMPLE
        Get-QueryResultValueKind -Value "007"
        String

    .NOTES
        No tracer preamble: this runs once per copied cell, on the clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlType,
        [switch]$SkipValueRefinement
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return "Null"
    }

    # Priority 1. Nothing populates SqlType yet, but the mapping is written out so that adding the
    # schema lookup later is a change to the caller and not to this function.
    if (![string]::IsNullOrWhiteSpace($SqlType)) {
        $DeclaredKind = Get-SqlTypeNameKind -SqlType $SqlType
        if (![string]::IsNullOrWhiteSpace($DeclaredKind)) {
            return $DeclaredKind
        }
    }

    # Priority 2. Unwrap a genuine PSObject wrapper first, because the wrapper's type is not the
    # value's type.
    #
    # The test is deliberately GetType() -eq and not -is: in PowerShell "-is [PSObject]" is true for
    # very nearly every value, so an -is test here would reach for .BaseObject on values that do not
    # have one and quietly turn them into $null - which would send every value down the String path.
    $BaseValue = $Value
    if ($null -ne $BaseValue -and $BaseValue.GetType() -eq [System.Management.Automation.PSObject]) {
        $BaseValue = $BaseValue.BaseObject
    }

    if ($BaseValue -is [bool]) { return "Boolean" }
    if ($BaseValue -is [byte[]]) { return "Binary" }
    if ($BaseValue -is [guid]) { return "Guid" }
    if ($BaseValue -is [datetime]) { return "DateTime" }
    if ($BaseValue -is [datetimeoffset]) { return "DateTimeOffset" }
    if ($BaseValue -is [timespan]) { return "Time" }
    if ($BaseValue -is [decimal]) { return "Decimal" }
    if ($BaseValue -is [double] -or $BaseValue -is [single]) { return "Float" }

    if ($BaseValue -is [byte] -or $BaseValue -is [sbyte] -or
        $BaseValue -is [int16] -or $BaseValue -is [uint16] -or
        $BaseValue -is [int32] -or $BaseValue -is [uint32] -or
        $BaseValue -is [int64] -or $BaseValue -is [uint64] -or
        $BaseValue -is [bigint]) {
        return "Integer"
    }

    if ($BaseValue -isnot [string]) {
        # Anything else - an unexpected CLR type, or a nested object - is rendered as text and
        # quoted. Quoting an unknown is always safe; leaving it unquoted never is.
        return "String"
    }

    if ($SkipValueRefinement.IsPresent) {
        return "String"
    }

    # Priority 3, and only from here down.
    return (Get-RefinedStringValueKind -Value $BaseValue)
}

function Get-SqlTypeNameKind {
    <#
    .SYNOPSIS
        Maps a declared SQL type name to a literal kind.

    .DESCRIPTION
        Split out of Get-QueryResultValueKind so the declared-type mapping can be exercised on its
        own, and so the schema resolution work described in issue #103 has a single place to feed.

    .PARAMETER SqlType
        A declared SQL type, with or without its precision or nullability, for example
        "nvarchar(50) NOT NULL".

    .OUTPUTS
        [string] the resolved kind, or $null when the type name is not recognised.

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlType
    )

    if ([string]::IsNullOrWhiteSpace($SqlType)) {
        return $null
    }

    # ToLowerInvariant, not ToLower. Under tr-TR the culture-sensitive fold turns "INT" into "ınt",
    # which matches nothing, and every type in the table below would silently fall through.
    $BaseName = ($SqlType.Trim() -split "[\s(]", 2)[0].ToLowerInvariant()

    switch ($BaseName) {
        "bit" { return "Boolean" }
        "tinyint" { return "Integer" }
        "smallint" { return "Integer" }
        "int" { return "Integer" }
        "bigint" { return "Integer" }
        "decimal" { return "Decimal" }
        "numeric" { return "Decimal" }
        "money" { return "Decimal" }
        "smallmoney" { return "Decimal" }
        "float" { return "Float" }
        "real" { return "Float" }
        # Date, not DateTime: a date column has no time part, and emitting one forces an implicit
        # conversion on the server. Only a DECLARED date reaches this - value refinement never
        # produces Date, because a bare "2019-01-01" in a string column is not safely a date.
        "date" { return "Date" }
        "datetime" { return "DateTime" }
        "datetime2" { return "DateTime" }
        "smalldatetime" { return "DateTime" }
        "datetimeoffset" { return "DateTimeOffset" }
        "time" { return "Time" }
        "uniqueidentifier" { return "Guid" }
        "binary" { return "Binary" }
        "varbinary" { return "Binary" }
        "image" { return "Binary" }
        "char" { return "String" }
        "varchar" { return "String" }
        "text" { return "String" }
        "nchar" { return "String" }
        "nvarchar" { return "String" }
        "ntext" { return "String" }
        default { return $null }
    }
}

function Get-RefinedStringValueKind {
    <#
    .SYNOPSIS
        Picks a narrower literal kind for a value already known to be a string.

    .DESCRIPTION
        Priority 3 of issue #103's resolution order, kept to exactly two refinements - an ISO 8601
        timestamp and a GUID - for the reasons set out in Get-QueryResultValueKind. Everything is
        matched against the whole value with an exact, invariant parse; no partial match refines
        anything.

    .PARAMETER Value
        The string value to inspect.

    .OUTPUTS
        [string] DateTime, DateTimeOffset, Guid, or String when nothing narrower applies.

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "String"
    }

    $Candidate = $Value.Trim()

    # A GUID, and only in the canonical hyphenated form. Accepting the braced or bare-hex forms
    # would start matching values that are not identifiers at all.
    if ($Candidate -match "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") {
        return "Guid"
    }

    # A time component is mandatory - see the note in Get-QueryResultValueKind about why a bare date
    # is left alone.
    if ($Candidate -notmatch "^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}") {
        return "String"
    }

    $Parsed = [datetimeoffset]::MinValue
    [string[]]$OffsetFormat = @(
        "yyyy-MM-ddTHH:mm:ss.FFFFFFFzzz",
        "yyyy-MM-ddTHH:mm:sszzz",
        "yyyy-MM-ddTHH:mm:ss.FFFFFFFZ",
        "yyyy-MM-ddTHH:mm:ssZ",
        "yyyy-MM-dd HH:mm:ss.FFFFFFFzzz",
        "yyyy-MM-dd HH:mm:sszzz"
    )

    # Only when the text actually carries an offset. Parsing an offset-less value as a
    # DateTimeOffset would invent the local machine's offset and bake it into the literal.
    if ($Candidate -match "(Z|[+-]\d{2}:\d{2})$") {
        if ([datetimeoffset]::TryParseExact($Candidate, $OffsetFormat, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
            return "DateTimeOffset"
        }

        return "String"
    }

    $ParsedDateTime = [datetime]::MinValue
    [string[]]$LocalFormat = @(
        "yyyy-MM-ddTHH:mm:ss.FFFFFFF",
        "yyyy-MM-ddTHH:mm:ss",
        "yyyy-MM-ddTHH:mm",
        "yyyy-MM-dd HH:mm:ss.FFFFFFF",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm"
    )

    if ([datetime]::TryParseExact($Candidate, $LocalFormat, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedDateTime)) {
        return "DateTime"
    }

    return "String"
}
