function ConvertTo-PowerShellLiteral {
    <#
    .SYNOPSIS
        Converts one query result value into one PowerShell literal.

    .DESCRIPTION
        The PowerShell half of issue #103's literal formatting, and pure for the same reason
        ConvertTo-SqlLiteral is.

        Two differences from the T-SQL side are worth knowing:

          * A boolean must be $true/$false, never the string 'False'. In PowerShell a non-empty
            string is truthy, so a copied 'False' evaluates to $true in the pasted script - the
            failure is silent and it inverts the test.
          * Dates, GUIDs and the other shapes that have no bare literal syntax are emitted with an
            explicit cast, so the pasted array rehydrates to the original typed values instead of
            to a list of strings. TypedLiteral turns that off for callers that want plain strings.

        Everything renders through InvariantCulture, and single quotes are doubled: a PowerShell
        single-quoted string has exactly the same escaping rule as a T-SQL character literal, and
        nothing else inside one is special.

    .PARAMETER Value
        The raw value read from the row property. May be $null or [DBNull]::Value.

    .PARAMETER Kind
        The literal kind, as resolved by Get-QueryResultValueKind. When omitted it is resolved here.

    .PARAMETER SqlType
        The declared SQL type of the column when it is known. Reserved for the schema resolution
        seam described in Get-QueryResultValueKind.

    .PARAMETER TypedLiteral
        Emit [datetime]'...', [guid]'...' and friends. Off, those values become plain quoted
        strings. Fed from the ArrayCopyPowerShellTypedLiterals setting.

    .OUTPUTS
        [string] a single PowerShell literal.

    .EXAMPLE
        ConvertTo-PowerShellLiteral -Value $false
        $false

    .EXAMPLE
        ConvertTo-PowerShellLiteral -Value "007"
        '007'

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
        [string]$SqlType,
        [switch]$TypedLiteral
    )

    if ([string]::IsNullOrWhiteSpace($Kind)) {
        $Kind = Get-QueryResultValueKind -Value $Value -SqlType $SqlType
    }

    if ($Kind -eq "Null" -or $null -eq $Value -or $Value -is [System.DBNull]) {
        return "`$null"
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
            if ([bool]$BaseValue) {
                return "`$true"
            }

            return "`$false"
        }

        "Integer" {
            return [string]::Format($Invariant, "{0}", $BaseValue)
        }

        "Decimal" {
            $DecimalText = ([decimal]$BaseValue).ToString($Invariant)
            if ($TypedLiteral.IsPresent) {
                # The cast keeps it a [decimal]; the bare number would be parsed as a [double] and
                # lose the exactness that made it a decimal in the first place.
                return "[decimal]'{0}'" -f $DecimalText
            }

            return $DecimalText
        }

        "Float" {
            $FloatText = Get-InvariantFloatText -Value $BaseValue
            if ($null -eq $FloatText) {
                return (Format-PowerShellStringLiteral -Text ([string]::Format($Invariant, "{0}", $BaseValue)))
            }

            return $FloatText
        }

        "DateTime" {
            $DateTimeValue = ConvertTo-InvariantDateTime -Value $BaseValue
            $DateTimeText = Format-InvariantDateTimeText -Value $DateTimeValue
            if ($TypedLiteral.IsPresent) {
                return "[datetime]'{0}'" -f $DateTimeText
            }

            return (Format-PowerShellStringLiteral -Text $DateTimeText)
        }

        "DateTimeOffset" {
            $OffsetValue = ConvertTo-InvariantDateTimeOffset -Value $BaseValue
            $OffsetText = $OffsetValue.ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz", $Invariant)
            if ($TypedLiteral.IsPresent) {
                return "[datetimeoffset]'{0}'" -f $OffsetText
            }

            return (Format-PowerShellStringLiteral -Text $OffsetText)
        }

        "Time" {
            $TimeValue = [timespan]$BaseValue
            $TimeText = if ($TimeValue.Days -eq 0) {
                $TimeValue.ToString("hh\:mm\:ss\.fffffff", $Invariant)
            }
            else {
                $TimeValue.ToString("c", $Invariant)
            }

            if ($TypedLiteral.IsPresent) {
                return "[timespan]'{0}'" -f $TimeText
            }

            return (Format-PowerShellStringLiteral -Text $TimeText)
        }

        "Guid" {
            $GuidValue = if ($BaseValue -is [guid]) { $BaseValue } else { [guid]::Parse([string]$BaseValue) }
            $GuidText = $GuidValue.ToString("D")
            if ($TypedLiteral.IsPresent) {
                return "[guid]'{0}'" -f $GuidText
            }

            return (Format-PowerShellStringLiteral -Text $GuidText)
        }

        "Binary" {
            $Bytes = [byte[]]$BaseValue
            if ($Bytes.Length -eq 0) {
                return "[byte[]]@()"
            }

            $HexValues = foreach ($Byte in $Bytes) {
                "0x{0}" -f $Byte.ToString("X2", $Invariant)
            }

            return "[byte[]]@({0})" -f ($HexValues -join ", ")
        }

        default {
            return (Format-PowerShellStringLiteral -Text ([string]::Format($Invariant, "{0}", $BaseValue)))
        }
    }
}

function Format-PowerShellStringLiteral {
    <#
    .SYNOPSIS
        Quotes and escapes a string as a PowerShell single-quoted literal.

    .DESCRIPTION
        Doubling the single quote is the whole escaping rule for a single-quoted PowerShell string:
        "$", backtick, "#" and the rest are all inert inside one. Using single quotes rather than
        double quotes is therefore what stops a copied value from being expanded - or executed - in
        the script it is pasted into.

    .PARAMETER Text
        The text to quote.

    .OUTPUTS
        [string] the quoted literal.

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($null -eq $Text) {
        $Text = ""
    }

    return "'{0}'" -f ($Text -replace "'", "''")
}
