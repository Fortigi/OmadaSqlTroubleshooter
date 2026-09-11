function ConvertTo-SqlLiteral {
    <#
    .SYNOPSIS
        Converts one query result value into one T-SQL literal.

    .DESCRIPTION
        Pure, and deliberately so: no WPF, no clipboard, no configuration lookup, nothing that
        cannot be asserted in Pester. The literal decisions of issue #103 all live here.

        Every rendering goes through InvariantCulture. A fixed format string is not a fixed
        rendering - under nl-NL the thread culture turns 12.50 into "12,50" and a date into
        "20-11-2019", and both are ambiguous or invalid on the server depending on SET DATEFORMAT
        and SET LANGUAGE.

        The N prefix is emitted only when it is earned: when the resolved SQL type is an n-type, or
        when the value actually carries a character outside the ASCII range. Prefixing everything
        is the tempting default and it is wrong - an nvarchar literal compared against a varchar
        column forces the conversion onto the column, which can turn an index seek into a scan.

        The output of this function is designed to be pasted into a query and executed, so the
        single-quote doubling below is a security boundary, not cosmetic.

    .PARAMETER Value
        The raw value read from the row property. May be $null or [DBNull]::Value.

    .PARAMETER Kind
        The literal kind, as resolved by Get-QueryResultValueKind. When omitted it is resolved here.

    .PARAMETER SqlType
        The declared SQL type of the column when it is known. Used only to decide the N prefix;
        nothing populates it yet. See Get-QueryResultValueKind for the schema resolution seam.

    .OUTPUTS
        [string] a single T-SQL literal.

    .EXAMPLE
        ConvertTo-SqlLiteral -Value "007"
        '007'

    .EXAMPLE
        ConvertTo-SqlLiteral -Value $true
        1

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
        [string]$Kind,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlType
    )

    if ([string]::IsNullOrWhiteSpace($Kind)) {
        $Kind = Get-QueryResultValueKind -Value $Value -SqlType $SqlType
    }

    if ($Kind -eq "Null" -or $null -eq $Value -or $Value -is [System.DBNull]) {
        return "NULL"
    }

    # GetType() -eq, not -is: see the note in Get-QueryResultValueKind about "-is [PSObject]" being
    # true for almost everything.
    $BaseValue = $Value
    if ($null -ne $BaseValue -and $BaseValue.GetType() -eq [System.Management.Automation.PSObject]) {
        $BaseValue = $BaseValue.BaseObject
    }

    $Invariant = [cultureinfo]::InvariantCulture

    switch ($Kind) {
        "Boolean" {
            # 1/0, never 'True'/'False'. A bit column compared against the string 'False' is a
            # conversion error, and that is the good outcome - the bad one is a column typed wide
            # enough to accept it and match nothing.
            #
            # Resolve-StrictBoolean rather than a [bool] cast: the cast is truthiness, so
            # [bool]'False' is $true and the literal would come out as 1 - the exact inversion this
            # issue is about. That matters once Kind can be Boolean because the COLUMN is a bit
            # while the value arrives as text, which is what the SqlType seam enables.
            $BooleanValue = Resolve-StrictBoolean -Value $BaseValue
            if ($null -eq $BooleanValue) {
                # Not a boolean this function can vouch for. Quote it and let the server reject it,
                # rather than guess a bit value that may be the opposite of the truth.
                return (Format-SqlStringLiteral -Text ([string]::Format($Invariant, "{0}", $BaseValue)) -SqlType $SqlType)
            }

            if ($BooleanValue) {
                return "1"
            }

            return "0"
        }

        "Integer" {
            return [string]::Format($Invariant, "{0}", $BaseValue)
        }

        "Decimal" {
            # decimal keeps its declared scale in the round trip, so 12.50 stays "12.50".
            return ([decimal]$BaseValue).ToString($Invariant)
        }

        "Float" {
            $FloatText = Get-InvariantFloatText -Value $BaseValue
            if ($null -eq $FloatText) {
                # Precision that cannot be round-tripped is shipped as a quoted literal rather than
                # as a number that is quietly wrong. numeric(38,0) deserialised as a Double is the
                # case this exists for.
                return (Format-SqlStringLiteral -Text ([string]::Format($Invariant, "{0}", $BaseValue)) -SqlType $SqlType)
            }

            return $FloatText
        }

        "Date" {
            # yyyyMMdd, the ISO 8601 basic form. It is the one date literal T-SQL reads identically
            # under every SET DATEFORMAT and SET LANGUAGE - "2019-01-01" is NOT, for a datetime
            # column - and it carries no time part to be implicitly converted away.
            $DateValue = ConvertTo-InvariantDateTime -Value $BaseValue
            return (Format-SqlStringLiteral -Text $DateValue.ToString("yyyyMMdd", $Invariant) -SqlType $SqlType -NeverPrefix)
        }

        "DateTime" {
            $DateTimeValue = ConvertTo-InvariantDateTime -Value $BaseValue
            return (Format-SqlStringLiteral -Text (Format-InvariantDateTimeText -Value $DateTimeValue) -SqlType $SqlType -NeverPrefix)
        }

        "DateTimeOffset" {
            $OffsetValue = ConvertTo-InvariantDateTimeOffset -Value $BaseValue
            return (Format-SqlStringLiteral -Text $OffsetValue.ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz", $Invariant) -SqlType $SqlType -NeverPrefix)
        }

        "Time" {
            $TimeValue = [timespan]$BaseValue
            $TimeText = if ($TimeValue.Days -eq 0) {
                $TimeValue.ToString("hh\:mm\:ss\.fffffff", $Invariant)
            }
            else {
                $TimeValue.ToString("c", $Invariant)
            }

            return (Format-SqlStringLiteral -Text $TimeText -SqlType $SqlType -NeverPrefix)
        }

        "Guid" {
            $GuidValue = if ($BaseValue -is [guid]) { $BaseValue } else { [guid]::Parse([string]$BaseValue) }
            return (Format-SqlStringLiteral -Text $GuidValue.ToString("D") -SqlType $SqlType -NeverPrefix)
        }

        "Binary" {
            $Bytes = [byte[]]$BaseValue
            if ($Bytes.Length -eq 0) {
                return "0x"
            }

            return ("0x{0}" -f [System.Convert]::ToHexString($Bytes))
        }

        default {
            return (Format-SqlStringLiteral -Text ([string]::Format($Invariant, "{0}", $BaseValue)) -SqlType $SqlType)
        }
    }
}

function Format-SqlStringLiteral {
    <#
    .SYNOPSIS
        Quotes and escapes a string as a T-SQL character literal.

    .DESCRIPTION
        Doubles every single quote and wraps the result in quotes. Nothing else inside a T-SQL
        character literal is special - "--", "/*" and "]" are inert there - so doubling the quote
        is both necessary and sufficient, and it is what keeps the generated text from being able
        to break out of the literal it belongs to.

    .PARAMETER Text
        The text to quote.

    .PARAMETER SqlType
        The declared SQL type of the column when known. An n-type earns the N prefix.

    .PARAMETER NeverPrefix
        Suppress the N prefix entirely. Used for the literals that are character-shaped only
        because T-SQL has no other syntax for them - dates, times, GUIDs - where the value is
        always ASCII and an N prefix would be noise.

    .OUTPUTS
        [string] the quoted literal, with the N prefix when it is earned.

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlType,
        [switch]$NeverPrefix
    )

    if ($null -eq $Text) {
        $Text = ""
    }

    $Escaped = $Text -replace "'", "''"

    if ($NeverPrefix.IsPresent) {
        return "'{0}'" -f $Escaped
    }

    if (Test-SqlUnicodeLiteralRequired -Text $Text -SqlType $SqlType) {
        return "N'{0}'" -f $Escaped
    }

    return "'{0}'" -f $Escaped
}

function Test-SqlUnicodeLiteralRequired {
    <#
    .SYNOPSIS
        Decides whether a character literal has earned its N prefix.

    .DESCRIPTION
        True when the column's declared type is an n-type, or when the value carries at least one
        character outside the ASCII range. Without the prefix such a literal is converted to the
        database code page on its way in and loses exactly the characters that made it interesting.

    .PARAMETER Text
        The value to inspect.

    .PARAMETER SqlType
        The declared SQL type of the column when known.

    .OUTPUTS
        [bool]

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlType
    )

    if (![string]::IsNullOrWhiteSpace($SqlType)) {
        # ToLowerInvariant: under tr-TR a culture-sensitive fold of "NVARCHAR" does not start with
        # a plain "n", and every n-type would lose its prefix.
        $BaseName = ($SqlType.Trim() -split "[\s(]", 2)[0].ToLowerInvariant()
        if ($BaseName -in @("nchar", "nvarchar", "ntext")) {
            return $true
        }

        if ($BaseName -in @("char", "varchar", "text")) {
            # An explicitly non-unicode column still earns the prefix when the value would not
            # survive without it; the alternative is silent character loss.
            return (Test-NonAsciiText -Text $Text)
        }
    }

    return (Test-NonAsciiText -Text $Text)
}

function Test-NonAsciiText {
    <#
    .SYNOPSIS
        Reports whether a string contains any character outside the ASCII range.

    .PARAMETER Text
        The value to inspect.

    .OUTPUTS
        [bool]

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }

    foreach ($Character in $Text.ToCharArray()) {
        if ([int]$Character -gt 127) {
            return $true
        }
    }

    return $false
}

function Get-InvariantFloatText {
    <#
    .SYNOPSIS
        Renders a floating point value as a round-trippable invariant number, or $null when it
        cannot be trusted.

    .DESCRIPTION
        Returns $null - meaning "do not emit this as a number" - in three cases:

          * NaN and the infinities, which have no T-SQL numeric literal at all;
          * a value whose "R" rendering does not parse back to the same value;
          * a value whose rendering needs exponential notation, which is where a numeric(38,0) that
            was deserialised into a Double ends up. The precision is already gone by then and no
            literal can bring it back, so the caller quotes it instead of shipping a number that is
            confidently wrong.

    .PARAMETER Value
        The Single or Double to render.

    .OUTPUTS
        [string] the rendered number, or $null.

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Value
    )

    $Invariant = [cultureinfo]::InvariantCulture
    $DoubleValue = [double]$Value

    if ([double]::IsNaN($DoubleValue) -or [double]::IsInfinity($DoubleValue)) {
        return $null
    }

    $Text = $DoubleValue.ToString("R", $Invariant)

    if ($Text -match "[eE]") {
        return $null
    }

    $RoundTrip = [double]0
    if (![double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, $Invariant, [ref]$RoundTrip)) {
        return $null
    }

    if ($RoundTrip -ne $DoubleValue) {
        return $null
    }

    return $Text
}

function ConvertTo-InvariantDateTime {
    <#
    .SYNOPSIS
        Coerces a value to [datetime], parsing a string with InvariantCulture.

    .DESCRIPTION
        A plain [datetime] cast would parse the string against the thread culture, which is the
        original bug in a different costume. Only the ISO shapes Get-RefinedStringValueKind already
        matched reach here, so an exact invariant parse is enough.

    .PARAMETER Value
        A [datetime], or a string in one of the accepted ISO 8601 shapes.

    .OUTPUTS
        [datetime]

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Value
    )

    if ($Value -is [datetime]) {
        return $Value
    }

    $Parsed = [datetime]::MinValue
    [string[]]$Format = @(
        "yyyy-MM-ddTHH:mm:ss.FFFFFFF",
        "yyyy-MM-ddTHH:mm:ss",
        "yyyy-MM-ddTHH:mm",
        "yyyy-MM-dd HH:mm:ss.FFFFFFF",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd"
    )

    if ([datetime]::TryParseExact([string]$Value, $Format, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
        return $Parsed
    }

    return [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
}

function ConvertTo-InvariantDateTimeOffset {
    <#
    .SYNOPSIS
        Coerces a value to [datetimeoffset], parsing a string with InvariantCulture.

    .PARAMETER Value
        A [datetimeoffset], or a string carrying an explicit offset.

    .OUTPUTS
        [datetimeoffset]

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([datetimeoffset])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        $Value
    )

    if ($Value -is [datetimeoffset]) {
        return $Value
    }

    return [datetimeoffset]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
}

function Format-InvariantDateTimeText {
    <#
    .SYNOPSIS
        Renders a [datetime] as an ISO 8601 string that T-SQL reads the same way under every
        SET DATEFORMAT and SET LANGUAGE.

    .DESCRIPTION
        Three fractional digits when the value lands on a whole millisecond, which is what a
        datetime column stores and what issue #103's mapping table asks for; seven otherwise, so a
        datetime2 value is not quietly truncated on its way to the clipboard.

    .PARAMETER Value
        The value to render.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [datetime]$Value
    )

    $Invariant = [cultureinfo]::InvariantCulture

    if (($Value.Ticks % 10000) -eq 0) {
        return $Value.ToString("yyyy-MM-ddTHH:mm:ss.fff", $Invariant)
    }

    return $Value.ToString("yyyy-MM-ddTHH:mm:ss.fffffff", $Invariant)
}
