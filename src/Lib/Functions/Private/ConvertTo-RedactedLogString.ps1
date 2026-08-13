function ConvertTo-RedactedLogString {
    <#
    .SYNOPSIS
        Serializes an object to JSON for logging with all secret material removed.

    .DESCRIPTION
        The single path by which request parameters, responses and configuration objects are allowed
        to reach the log. Sensitive properties are masked by name, credentials and secure strings by
        type, and bulk data is reduced to a shape summary so result rows never land in a log file that
        a user can export and attach to a support ticket.

        NOTE: neither function in this file may carry the standard $Script:Tracer preamble or call
        Write-LogOutput. The tracer preamble in every other function routes through this one, and
        Write-LogOutput routes through Protect-LogMessage - instrumenting the helpers would make them
        call themselves.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject,
        [int]$MaxDepth = 6,
        [int]$MaxStringLength = 512
    )

    try {
        $Redacted = ConvertTo-RedactedLogValue -Value $InputObject -Depth 0 -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited ([System.Collections.Generic.List[object]]::new()) -MaskValues $false
        if ($null -eq $Redacted) {
            return "null"
        }

        return ($Redacted | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue)
    }
    catch {
        # Failing open would leak the very thing this function exists to hide.
        return "<redaction failed: {0}>" -f $_.Exception.Message
    }
}

function ConvertTo-RedactedLogValue {
    <#
    .SYNOPSIS
        Recursive walker behind ConvertTo-RedactedLogString. Returns a redacted clone, not a string.
    #>
    [CmdLetBinding()]
    param(
        [AllowNull()]
        $Value,
        [int]$Depth,
        [int]$MaxDepth,
        [int]$MaxStringLength,
        [System.Collections.Generic.List[object]]$Visited,
        [bool]$MaskValues
    )

    $RedactedToken = "***REDACTED***"

    # Property names that identify secret material. Matched as a case-insensitive substring so
    # composites such as X-CSRF-Token, RefreshToken and SessionCookie are covered too.
    $SensitiveNamePatterns = @(
        "authorization", "cookie", "credential", "password", "pwd", "secret", "token",
        "apikey", "api_key", "clientsecret", "sessionkey", "bearer", "csrf", "assertion",
        "privatekey", "connectionstring"
    )

    if ($null -eq $Value) {
        return $null
    }

    # Type rules first - these hold regardless of the property name the value arrived under.
    if ($Value -is [System.Security.SecureString]) {
        return $RedactedToken
    }

    if ($Value -is [System.Management.Automation.PSCredential]) {
        # The user name is diagnostic and not secret; the password never leaves the SecureString.
        return "PSCredential(UserName={0})" -f $Value.UserName
    }

    if ($Value -is [System.Net.NetworkCredential]) {
        return "NetworkCredential(UserName={0})" -f $Value.UserName
    }

    if ($Value -is [byte[]]) {
        return "Byte[{0}]" -f $Value.Length
    }

    if ($Value -is [System.Net.CookieContainer]) {
        return "CookieContainer(Count={0})" -f $Value.Count
    }

    if ($Value -is [System.Net.CookieCollection]) {
        return "CookieCollection(Count={0})" -f $Value.Count
    }

    if ($Value -is [string]) {
        if ($MaskValues) {
            return "String({0})" -f $Value.Length
        }

        if ($Value.Length -gt $MaxStringLength) {
            return "{0}...(truncated, {1} chars)" -f $Value.Substring(0, $MaxStringLength), $Value.Length
        }

        return $Value
    }

    if ($Value -is [ValueType] -or $Value -is [uri] -or $Value -is [System.Management.Automation.SwitchParameter]) {
        if ($MaskValues) {
            return $Value.GetType().Name
        }

        return $Value
    }

    if ($Depth -ge $MaxDepth) {
        return "<max depth {0} reached: {1}>" -f $MaxDepth, $Value.GetType().Name
    }

    # Live WPF, session and response objects are cyclic - without this the walker never returns.
    foreach ($Seen in $Visited) {
        if ([object]::ReferenceEquals($Seen, $Value)) {
            return "<circular reference: {0}>" -f $Value.GetType().Name
        }
    }
    $Visited.Add($Value)

    if ($Value -is [System.Collections.IDictionary]) {
        $Result = [ordered]@{}
        foreach ($Key in @($Value.Keys)) {
            $Result[[string]$Key] = Get-RedactedMemberValue -Name ([string]$Key) -MemberValue $Value[$Key] -Depth $Depth -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $MaskValues -SensitiveNamePatterns $SensitiveNamePatterns -RedactedToken $RedactedToken
        }

        return $Result
    }

    if ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable]) {
        $Items = @($Value)
        $ItemCount = ($Items | Measure-Object).Count
        if ($ItemCount -gt 3) {
            # Bulk data - result rows, schema tables. Log the shape, never the contents.
            $ElementType = "Object"
            if ($null -ne $Items[0]) {
                $ElementType = $Items[0].GetType().Name
            }

            return "Array[{0}] of {1}" -f $ItemCount, $ElementType
        }

        $Result = @()
        foreach ($Item in $Items) {
            $Result += , (ConvertTo-RedactedLogValue -Value $Item -Depth ($Depth + 1) -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $MaskValues)
        }

        return $Result
    }

    # Anything else: walk its properties, tolerating members that throw when read.
    $Result = [ordered]@{}
    try {
        foreach ($Property in $Value.PSObject.Properties) {
            try {
                $Result[$Property.Name] = Get-RedactedMemberValue -Name $Property.Name -MemberValue $Property.Value -Depth $Depth -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $MaskValues -SensitiveNamePatterns $SensitiveNamePatterns -RedactedToken $RedactedToken
            }
            catch {
                $Result[$Property.Name] = "<unreadable>"
            }
        }
    }
    catch {
        return "<{0}>" -f $Value.GetType().Name
    }

    if ($Result.Count -le 0) {
        return $Value.ToString()
    }

    return $Result
}

function Get-RedactedMemberValue {
    <#
    .SYNOPSIS
        Applies the name-based rules for a single member, then hands off to the recursive walker.
    #>
    [CmdLetBinding()]
    param(
        [string]$Name,
        [AllowNull()]
        $MemberValue,
        [int]$Depth,
        [int]$MaxDepth,
        [int]$MaxStringLength,
        [System.Collections.Generic.List[object]]$Visited,
        [bool]$MaskValues,
        [string[]]$SensitiveNamePatterns,
        [string]$RedactedToken
    )

    # Credential objects are handled by the type rules in the walker, which keep the user name -
    # knowing which account authenticated is diagnostic - while the password stays in its
    # SecureString. Applying the name rule here instead would throw that away for no gain.
    $HandledByTypeRule = $MemberValue -is [System.Management.Automation.PSCredential] -or
        $MemberValue -is [System.Net.NetworkCredential] -or
        $MemberValue -is [System.Security.SecureString]

    if (-not $HandledByTypeRule) {
        foreach ($Pattern in $SensitiveNamePatterns) {
            if ($Name -like "*$Pattern*") {
                return $RedactedToken
            }
        }
    }

    # Request bodies keep their keys and value shapes - enough to tell what was sent - but no values.
    $ChildMaskValues = $MaskValues
    if ($Name -eq "Body") {
        $ChildMaskValues = $true
    }

    return ConvertTo-RedactedLogValue -Value $MemberValue -Depth ($Depth + 1) -MaxDepth $MaxDepth -MaxStringLength $MaxStringLength -Visited $Visited -MaskValues $ChildMaskValues
}
