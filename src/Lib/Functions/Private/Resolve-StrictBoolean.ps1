function Resolve-StrictBoolean {
    <#
    .SYNOPSIS
        Resolves a value to a boolean only when it genuinely is one, and reports failure rather than
        guessing.

    .DESCRIPTION
        PowerShell's [bool] cast is truthiness, not parsing. Every non-empty string is $true, so:

            [bool]'False' -> True
            [bool]'false' -> True
            [bool]'0'     -> True

        That is the same class of bug issue #103 exists to fix - a value that means "no" silently
        becoming "yes" - and a plain [bool] cast reintroduces it anywhere a boolean can arrive as
        text: a bit column typed from the schema, or a hand-edited configuration file.

        This returns $null when the value is not a boolean it can vouch for, so the caller can fall
        back deliberately instead of inheriting a wrong answer. Accepted:

          * a real [bool];
          * a string that [bool]::TryParse accepts ("true"/"false", any casing);
          * an INTEGER or [decimal], where 0 is false and anything else is true - which is how a
            bit column's value arrives when it is carried as 0/1.

        Everything else resolves to $null, including the empty string and - deliberately - [double]
        and [single]. A floating point value is not a truth value: 1e-300 is not meaningfully "true"
        and rounding decides the answer. Nothing produces a bit as a float, so accepting one would
        only widen the guess this function exists to refuse.

    .PARAMETER Value
        The value to resolve.

    .OUTPUTS
        [bool] when the value is definitely a boolean, otherwise $null.

    .EXAMPLE
        Resolve-StrictBoolean -Value "False"
        False

    .EXAMPLE
        Resolve-StrictBoolean -Value "maybe"
        (returns $null)

    .NOTES
        No tracer preamble: called from the per-cell clipboard path.
    #>

    [CmdLetBinding()]
    [OutputType([System.Nullable[bool]])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        $Value
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $null
    }

    # GetType() -eq, not -is: see the note in Get-QueryResultValueKind about "-is [PSObject]" being
    # true for almost everything.
    $BaseValue = $Value
    if ($BaseValue.GetType() -eq [System.Management.Automation.PSObject]) {
        $BaseValue = $BaseValue.BaseObject
    }

    if ($BaseValue -is [bool]) {
        return [bool]$BaseValue
    }

    if ($BaseValue -is [string]) {
        $Parsed = $false
        # TryParse, not a cast. This is the whole point of the function.
        if ([bool]::TryParse($BaseValue.Trim(), [ref]$Parsed)) {
            return $Parsed
        }

        return $null
    }

    if ($BaseValue -is [byte] -or $BaseValue -is [sbyte] -or
        $BaseValue -is [int16] -or $BaseValue -is [uint16] -or
        $BaseValue -is [int32] -or $BaseValue -is [uint32] -or
        $BaseValue -is [int64] -or $BaseValue -is [uint64] -or
        $BaseValue -is [decimal]) {
        return ([decimal]$BaseValue -ne [decimal]0)
    }

    return $null
}
