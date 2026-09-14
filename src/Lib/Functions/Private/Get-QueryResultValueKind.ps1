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

function Get-CanonicalNumericStringKind {
    <#
    .SYNOPSIS
        Reports whether a string is a number written in exactly one, unambiguous way - and which
        kind of number it is.

    .DESCRIPTION
        The gate on priority 3's only promotion, added by issue #120. Against a response that types
        every column as a string there is no CLR type left to read, and #103 rejected text sniffing
        for a very good reason: it turns the code "007" into the number 7.

        The answer is to sniff CANONICAL numbers only. A canonical number is one whose text is the
        only text that renders it, so emitting it unquoted cannot change what the value is:

          * an optional leading minus, never a leading plus;
          * no leading zero unless the integer part IS zero, so "007" is refused;
          * at least one digit after the decimal point when there is one, so "12." is refused;
          * no thousands separator, no exponent, no currency symbol, no percent sign, no
            surrounding whitespace and no hexadecimal;
          * it must round-trip - parsing the text and rendering it invariantly has to give the text
            back, which is what stops a value too wide for Int64 or Decimal from being promoted.

        Anything else is a string, because for anything else the quoted literal is the only literal
        that is certainly right.

    .PARAMETER Value
        The text to inspect.

    .OUTPUTS
        [string] Integer or Decimal, or $null when the text is not a canonical number.

    .NOTES
        No tracer preamble: called once per copied cell.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $null
    }

    $Invariant = [cultureinfo]::InvariantCulture

    if ($Value -match "^-?(0|[1-9][0-9]*)$") {
        $Integer = [long]0
        if ([long]::TryParse($Value, [System.Globalization.NumberStyles]::AllowLeadingSign, $Invariant, [ref]$Integer) -and
            $Integer.ToString($Invariant) -ceq $Value) {
            return "Integer"
        }

        return $null
    }

    if ($Value -match "^-?(0|[1-9][0-9]*)\.[0-9]+$") {
        $Decimal = [decimal]0
        if ([decimal]::TryParse($Value, ([System.Globalization.NumberStyles]::AllowLeadingSign -bor [System.Globalization.NumberStyles]::AllowDecimalPoint), $Invariant, [ref]$Decimal) -and
            $Decimal.ToString($Invariant) -ceq $Value) {
            return "Decimal"
        }

        return $null
    }

    return $null
}

function Test-QueryResultRowIsUntyped {
    <#
    .SYNOPSIS
        Reports whether a result set carries no type information of its own.

    .DESCRIPTION
        The switch that decides whether the value-promotion of issue #120 may run at all, and the
        reason promoting numbers out of text does not re-break issue #103's acceptance criterion 1.

        A response that types its values is evidence: the endpoint sent a JSON string because the
        column is textual, so "12345" in an nvarchar column must stay quoted. A response that types
        NOTHING is no evidence at all, and quoting everything is exactly the reported bug. The two
        cannot be told apart one column at a time - a single text column looks identical in both -
        so the question is asked of the whole result set, once per copy.

        A number or a boolean is the evidence looked for, because those are the two shapes only a
        typed JSON payload produces. A [datetime] is deliberately NOT evidence: ConvertFrom-Json
        rehydrates an ISO 8601 timestamp to a [datetime] whether the JSON quoted it or not, so a
        date proves nothing about the rest of the payload.

        It reads at most MaximumRow rows. A typed response shows a number in its first row, and the
        grid can hold thousands: scanning all of them would cost the whole result set per copy to
        answer a question the first rows already answer.

    .PARAMETER Row
        The bound result rows.

    .PARAMETER MaximumRow
        How many rows to inspect before concluding.

    .OUTPUTS
        [bool] $true when nothing in the inspected rows carries a type.

    .NOTES
        No tracer preamble: called once per copy, and its parameter is the result set.
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Row,
        [Parameter(Mandatory = $false)]
        [int]$MaximumRow = 200
    )

    $Inspected = 0

    foreach ($CurrentRow in @($Row)) {
        if ($null -eq $CurrentRow) {
            continue
        }

        if ($Inspected -ge $MaximumRow) {
            break
        }

        $Inspected++

        foreach ($Property in $CurrentRow.PSObject.Properties) {
            $Value = $Property.Value
            if ($null -eq $Value) {
                continue
            }

            if ($Value.GetType() -eq [System.Management.Automation.PSObject]) {
                $Value = $Value.BaseObject
            }

            if ($Value -is [bool] -or $Value -is [decimal] -or $Value -is [double] -or $Value -is [single] -or
                $Value -is [byte] -or $Value -is [sbyte] -or
                $Value -is [int16] -or $Value -is [uint16] -or
                $Value -is [int32] -or $Value -is [uint32] -or
                $Value -is [int64] -or $Value -is [uint64] -or
                $Value -is [bigint]) {
                return $false
            }
        }
    }

    # No rows at all counts as untyped, and costs nothing: with no values there is no column to
    # promote either.
    return $true
}

function Resolve-ColumnBooleanValue {
    <#
    .SYNOPSIS
        Resolves a value to a boolean for a column that is DECLARED to be a bit.

    .DESCRIPTION
        Resolve-StrictBoolean deliberately refuses the string "1": on its own, text is not evidence
        of a truth value, and that refusal is pinned by its own tests.

        A column the schema declares as a bit is a different question, and issue #120 is where the
        difference shows up. A response that renders every value as text renders a bit as "0"/"1" or
        as "True"/"False", and with the declared type in hand there is no guess left to make - the
        column IS a bit. So exactly those shapes are accepted here, on top of everything
        Resolve-StrictBoolean already vouches for, and the integer rule that function already
        documents is what decides "0" and "1" rather than a second copy of that decision.

        Nothing else widens: any other text still resolves to $null, and the caller then quotes the
        value rather than emitting a bit it cannot vouch for.

    .PARAMETER Value
        The value to resolve.

    .OUTPUTS
        [bool], or $null when the value is not a boolean this can vouch for.

    .NOTES
        No tracer preamble: called once per copied cell.
    #>

    [CmdLetBinding()]
    [OutputType([System.Nullable[bool]])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    $Resolved = Resolve-StrictBoolean -Value $Value
    if ($null -ne $Resolved) {
        return $Resolved
    }

    $BaseValue = $Value
    if ($null -ne $BaseValue -and $BaseValue.GetType() -eq [System.Management.Automation.PSObject]) {
        $BaseValue = $BaseValue.BaseObject
    }

    if ($BaseValue -isnot [string]) {
        return $null
    }

    $Text = $BaseValue.Trim()
    if ((Get-CanonicalNumericStringKind -Value $Text) -ne "Integer") {
        return $null
    }

    return (Resolve-StrictBoolean -Value ([long]$Text))
}

function Test-QueryResultValueFitsKind {
    <#
    .SYNOPSIS
        Reports whether a value can honestly be emitted as the given literal kind.

    .DESCRIPTION
        The corroboration step of issue #120, and the reason a declared SQL type cannot corrupt a
        value. Priority 1 answers from the schema, which is a NAME-based resolution against a cache
        that may be older than the database - so before a whole column is formatted as its declared
        type, every value in it has to be one that type can actually hold. A value that is not
        degrades the column to String, which is always safe.

        It is also what keeps issue #103's acceptance criterion 2 true whatever the schema says:
        "007" does not fit Integer, because the only integer literal for it is 7, and 7 is a
        different value.

        $null and DBNull fit every kind: they are emitted as NULL whatever the column resolved to.

    .PARAMETER Value
        The value to check.

    .PARAMETER Kind
        The literal kind the column resolved to.

    .OUTPUTS
        [bool]

    .NOTES
        No tracer preamble: called once per copied cell.
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value,
        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    if ($null -eq $Value -or $Value -is [System.DBNull] -or $Kind -eq "Null" -or $Kind -eq "String") {
        return $true
    }

    $BaseValue = $Value
    if ($BaseValue.GetType() -eq [System.Management.Automation.PSObject]) {
        $BaseValue = $BaseValue.BaseObject
    }

    # A value that already IS the CLR type the kind describes needs no text to be trusted. The
    # string cases below are the ones the schema seam introduced.
    $Invariant = [cultureinfo]::InvariantCulture
    $Text = if ($BaseValue -is [string]) { $BaseValue.Trim() } else { $null }

    switch ($Kind) {
        "Boolean" {
            return ($null -ne (Resolve-ColumnBooleanValue -Value $BaseValue))
        }

        "Integer" {
            if ($BaseValue -is [bool]) { return $false }
            if ($null -ne $Text) { return ((Get-CanonicalNumericStringKind -Value $Text) -eq "Integer") }

            return ($BaseValue -is [byte] -or $BaseValue -is [sbyte] -or
                $BaseValue -is [int16] -or $BaseValue -is [uint16] -or
                $BaseValue -is [int32] -or $BaseValue -is [uint32] -or
                $BaseValue -is [int64] -or $BaseValue -is [uint64] -or
                $BaseValue -is [bigint])
        }

        "Decimal" {
            if ($BaseValue -is [bool]) { return $false }
            if ($null -ne $Text) { return ($null -ne (Get-CanonicalNumericStringKind -Value $Text)) }

            return ($BaseValue -is [decimal] -or $BaseValue -is [byte] -or $BaseValue -is [sbyte] -or
                $BaseValue -is [int16] -or $BaseValue -is [uint16] -or
                $BaseValue -is [int32] -or $BaseValue -is [uint32] -or
                $BaseValue -is [int64] -or $BaseValue -is [uint64])
        }

        "Float" {
            if ($BaseValue -is [bool]) { return $false }
            if ($null -ne $Text) {
                $Double = [double]0
                return [double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, $Invariant, [ref]$Double)
            }

            return ($BaseValue -is [double] -or $BaseValue -is [single] -or $BaseValue -is [decimal] -or
                $BaseValue -is [int16] -or $BaseValue -is [int32] -or $BaseValue -is [int64])
        }

        "Guid" {
            if ($BaseValue -is [guid]) { return $true }
            if ($null -eq $Text) { return $false }

            $Guid = [guid]::Empty
            return [guid]::TryParse($Text, [ref]$Guid)
        }

        "Binary" {
            return ($BaseValue -is [byte[]])
        }

        "Time" {
            if ($BaseValue -is [timespan]) { return $true }
            if ($null -eq $Text) { return $false }

            $Time = [timespan]::Zero
            return [timespan]::TryParse($Text, $Invariant, [ref]$Time)
        }

        "DateTimeOffset" {
            if ($BaseValue -is [datetimeoffset]) { return $true }
            if ($null -eq $Text) { return $false }

            $Offset = [datetimeoffset]::MinValue
            return [datetimeoffset]::TryParse($Text, $Invariant, [System.Globalization.DateTimeStyles]::None, [ref]$Offset)
        }

        default {
            # Date and DateTime. An INVARIANT parse only: a value rendered in the tenant's locale
            # ("20-11-2019") is deliberately not accepted, because reading it needs a culture this
            # process cannot know is the right one, and picking one is a guess that silently swaps
            # the day and the month (issue #95 is the same trap on the history grid).
            if ($BaseValue -is [datetime]) { return $true }
            if ($null -eq $Text) { return $false }

            $DateTime = [datetime]::MinValue
            return [datetime]::TryParse($Text, $Invariant, [System.Globalization.DateTimeStyles]::None, [ref]$DateTime)
        }
    }
}
