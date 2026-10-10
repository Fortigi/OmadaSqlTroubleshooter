function ConvertFrom-OmadaAppPageVars {
    <#
    .SYNOPSIS
        Parses the settings Omada embeds in a page's `appPageVars` assignment into one lookup.

    .DESCRIPTION
        Issue #165. Every Omada page carries the tenant's application settings inline, as a JavaScript
        object literal assigned to `appPageVars`. Reading a setting from there costs ONE request;
        reading the same setting with a SQL query costs up to four and creates and deletes a temporary
        query object on the tenant, because every execute goes through Invoke-OmadaExecutePipeline.

        Generic on purpose. The feature that needed this wants one flag (`isIngestionEnabled`), but a
        parser that returned only that flag would have to be rewritten for the next one - so this
        returns EVERY setting it can see and lets the caller ask for what it wants.

        WHY IT IS NOT A REGEX, AND NOT A WHOLE-LITERAL JSON CONVERSION.

        The block is a JavaScript literal, not JSON: bare keys (`identityUserName:`) and single-quoted
        strings (`'SYSTEM'`). The obvious approach - rewrite the whole thing into JSON and parse it -
        has to quote bare keys and convert quote characters without touching the braces, colons,
        commas and quotes that appear INSIDE string values, of which this payload has many. So instead
        the block's top-level pairs are walked directly, and ConvertFrom-Json is used only on values
        that are already valid JSON.

        That distinction is load-bearing for real payloads:

          custSettings       a JSON object with double-quoted keys - parsed.
          languages          likewise.
          uiHomePageActions  a JSON document carried as an escaped STRING inside custSettings, which
                             one level of parsing leaves as text - so Expand-OmadaAppPageVarNestedJson
                             walks a parsed value and parses those too.
          gridEquipmentDims  single-quoted and JS-ish (`'{ counterHeight: 32, ... }'`). Measured, not
                             assumed: PowerShell 7's ConvertFrom-Json accepts bare keys, so this
                             parses into a dictionary rather than failing. The "keep the string"
                             fallback is still there for text that is not an object at all.

        `custSettings` is flattened into the same lookup as well as being kept nested, because the
        settings a caller wants are spread across both levels: `isIngestionEnabled` is top-level while
        `oDWMaximumObjectsPerRequest` and friends live inside `custSettings`, and a caller should not
        have to know which.

        THREE-STATE, by omission: a key that is not in the page is simply absent from the lookup, which
        is not the same as a key whose value is `false`. Callers must distinguish the two - an older
        tenant that does not publish a flag has not told us the flag is off.

        TRACED, but without its parameters. The one parameter is a page of the tenant's own
        configuration (issue #61 section 5), so the preamble writes only $MyInvocation.Statement - the
        text of the call, never the value passed. The helpers below are traced the same way, except
        Expand-OmadaAppPageVarNestedJson, which recurses once per nested element and would flood the
        trace; its comment says so.

    .PARAMETER Html
        The page body. Null, empty, or a page with no `appPageVars` assignment yields an empty lookup
        rather than an error: a caller that cannot read a setting has to cope with that anyway, and a
        page shape we do not recognise is not an exceptional condition.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] - case-insensitive, possibly empty.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Html
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    # [ordered] rather than a plain hashtable: the page's own order is the most useful order to log
    # and to read, and PowerShell's ordered dictionary compares keys case-insensitively, which is what
    # lets a caller write isIngestionEnabled however the page spells it.
    $Result = [ordered]@{}

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return $Result
    }

    $Block = Get-OmadaAppPageVarBlock -Html $Html
    if ([string]::IsNullOrWhiteSpace($Block)) {
        return $Result
    }

    foreach ($Pair in (Split-OmadaAppPageVarPair -Block $Block)) {
        $Result[$Pair.Name] = ConvertFrom-OmadaAppPageVarValue -RawValue $Pair.RawValue
    }

    # The nested level, flattened alongside the top one. A top-level key WINS over a custSettings key
    # of the same name: the outer assignment is what the page itself chose to expose.
    if ($Result.Contains("custSettings") -and $Result["custSettings"] -is [System.Collections.IDictionary]) {
        foreach ($Key in @($Result["custSettings"].Keys)) {
            if (-not $Result.Contains([string]$Key)) {
                $Result[[string]$Key] = $Result["custSettings"][$Key]
            }
        }
    }

    return $Result
}

function Get-OmadaAppPageVarBlock {
    <#
    .SYNOPSIS
        The inside of the `appPageVars={ ... }` object literal, or $null.

    .DESCRIPTION
        A BALANCED-BRACE scan, not a regex. The literal's own values contain `{` and `}` - inside the
        custSettings JSON, and inside strings such as uiHomePageActions - so a pattern that stops at
        the first `}` truncates the block and one that stops at the last `}` swallows the rest of the
        page's script. Only a scan that counts depth while skipping string contents can find the end.

    .PARAMETER Html
        The page body.

    .OUTPUTS
        [string] the text between the outermost braces, or $null when there is no such assignment.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    $AssignmentIndex = $Html.IndexOf("appPageVars", [System.StringComparison]::Ordinal)
    if ($AssignmentIndex -lt 0) {
        return $null
    }

    $OpenIndex = $Html.IndexOf("{", $AssignmentIndex)
    if ($OpenIndex -lt 0) {
        return $null
    }

    $Depth = 0
    $QuoteCharacter = [char]0
    $IsEscaped = $false

    for ($Index = $OpenIndex; $Index -lt $Html.Length; $Index++) {
        $Character = $Html[$Index]

        if ($IsEscaped) {
            $IsEscaped = $false
            continue
        }

        if ($Character -eq "\") {
            $IsEscaped = $true
            continue
        }

        if ($QuoteCharacter -ne [char]0) {
            if ($Character -eq $QuoteCharacter) {
                $QuoteCharacter = [char]0
            }

            continue
        }

        if ($Character -eq "'" -or $Character -eq '"') {
            $QuoteCharacter = $Character
            continue
        }

        if ($Character -eq "{") {
            $Depth++
            continue
        }

        if ($Character -eq "}") {
            $Depth--
            if ($Depth -eq 0) {
                return $Html.Substring($OpenIndex + 1, $Index - $OpenIndex - 1)
            }
        }
    }

    # Unbalanced - a truncated page, or markup this parser does not understand. Reported as "no block"
    # rather than as a guess at where it should have ended.
    return $null
}

function Split-OmadaAppPageVarPair {
    <#
    .SYNOPSIS
        The block's TOP-LEVEL `name: value` pairs, with each value left as raw text.

    .DESCRIPTION
        Splits on commas and colons that are at depth zero and outside any string, so a nested object,
        an array, or a string containing either stays in one piece. The value is not interpreted here -
        ConvertFrom-OmadaAppPageVarValue decides what it is.

    .PARAMETER Block
        The inside of the object literal, from Get-OmadaAppPageVarBlock.

    .OUTPUTS
        [PSCustomObject[]] with Name and RawValue. Always an array, possibly empty.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Block
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    $Pair = [System.Collections.Generic.List[object]]::new()

    $Depth = 0
    $QuoteCharacter = [char]0
    $IsEscaped = $false
    $SeparatorIndex = -1
    $Start = 0

    for ($Index = 0; $Index -lt $Block.Length; $Index++) {
        $Character = $Block[$Index]

        if ($IsEscaped) {
            $IsEscaped = $false
            continue
        }

        if ($Character -eq "\") {
            $IsEscaped = $true
            continue
        }

        if ($QuoteCharacter -ne [char]0) {
            if ($Character -eq $QuoteCharacter) {
                $QuoteCharacter = [char]0
            }

            continue
        }

        if ($Character -eq "'" -or $Character -eq '"') {
            $QuoteCharacter = $Character
            continue
        }

        if ($Character -eq "{" -or $Character -eq "[") {
            $Depth++
            continue
        }

        if ($Character -eq "}" -or $Character -eq "]") {
            $Depth--
            continue
        }

        # The FIRST colon at depth zero separates this pair's name from its value. Later ones belong to
        # the value - a URL's scheme, or a time span such as "00:01:00".
        if ($Character -eq ":" -and $Depth -eq 0 -and $SeparatorIndex -lt 0) {
            $SeparatorIndex = $Index
            continue
        }

        if ($Character -eq "," -and $Depth -eq 0) {
            $Private:Entry = New-OmadaAppPageVarPair -Block $Block -Start $Start -SeparatorIndex $SeparatorIndex -End $Index
            if ($null -ne $Private:Entry) {
                $Pair.Add($Private:Entry)
            }

            $Start = $Index + 1
            $SeparatorIndex = -1
        }
    }

    # The last pair has no trailing comma to close it.
    $Private:Final = New-OmadaAppPageVarPair -Block $Block -Start $Start -SeparatorIndex $SeparatorIndex -End $Block.Length
    if ($null -ne $Private:Final) {
        $Pair.Add($Private:Final)
    }

    return , $Pair.ToArray()
}

function New-OmadaAppPageVarPair {
    <#
    .SYNOPSIS
        One Name/RawValue pair out of the block, or $null when the span is not a pair.

    .DESCRIPTION
        Its own function because Split-OmadaAppPageVarPair builds a pair in two places - at every comma
        and once more at the end of the block - and two copies of the trimming and the empty checks
        would be two places to get them wrong.

    .OUTPUTS
        [PSCustomObject] with Name and RawValue, or $null.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Block,

        [Parameter(Mandatory = $true)]
        [int]$Start,

        [Parameter(Mandatory = $true)]
        [int]$SeparatorIndex,

        [Parameter(Mandatory = $true)]
        [int]$End
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    if ($SeparatorIndex -lt $Start -or $SeparatorIndex -ge $End) {
        return $null
    }

    $Name = $Block.Substring($Start, $SeparatorIndex - $Start).Trim()
    # A quoted key is legal JavaScript too, and the quotes are not part of the name.
    $Name = $Name.Trim("'", '"').Trim()
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    return [PSCustomObject]@{
        Name     = $Name
        RawValue = $Block.Substring($SeparatorIndex + 1, $End - $SeparatorIndex - 1).Trim()
    }
}

function ConvertFrom-OmadaAppPageVarValue {
    <#
    .SYNOPSIS
        One raw value from the literal, as the type it represents.

    .DESCRIPTION
        `true`/`false` become booleans, because the callers of this parser ask yes/no questions and a
        string "true" would make every one of them remember to compare text. Numbers become numbers.
        A quoted string loses its quotes. An object or array is parsed as JSON.

        Then the recursion that the real payload makes necessary: a STRING whose content looks like
        JSON is parsed too, because several settings are JSON documents carried as escaped strings
        (uiHomePageActions, authElementPermissions). The attempt is allowed to fail and keep the
        string - gridEquipmentDims looks like an object but is JS-ish and not valid JSON, and throwing
        on it would lose every other setting in the page.

    .PARAMETER RawValue
        The value's text, already trimmed.

    .OUTPUTS
        The value, or $null.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RawValue
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    if ([string]::IsNullOrWhiteSpace($RawValue)) {
        return $null
    }

    if ($RawValue -eq "true") {
        return $true
    }

    if ($RawValue -eq "false") {
        return $false
    }

    if ($RawValue -eq "null" -or $RawValue -eq "undefined") {
        return $null
    }

    # INVARIANT CULTURE, and the overload matters. The two-argument TryParse parses under the CURRENT
    # culture, so on a host whose culture uses "." as a group separator (de-DE, for instance) a value
    # of 1.5 parses as 15. This block is machine-generated JavaScript and is always invariant, which
    # makes the host's culture simply the wrong question to ask of it.
    #
    # The flag this feature consumes is a boolean, so nothing shipped was affected - but this parser
    # is documented as generic ("Numbers become numbers"), and a latent trap in a generic helper is
    # worse than one in a specific caller. Same convention as Get-QueryResultValueKind.ps1 and
    # ConvertTo-SqlLiteral.ps1, which both pass NumberStyles::Float with the invariant culture.
    $Numeric = 0.0
    if ([double]::TryParse($RawValue, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Numeric)) {
        return $Numeric
    }

    $FirstCharacter = $RawValue[0]

    if ($FirstCharacter -eq "'" -or $FirstCharacter -eq '"') {
        $Text = $RawValue.Substring(1)
        if ($Text.Length -gt 0 -and $Text[$Text.Length - 1] -eq $FirstCharacter) {
            $Text = $Text.Substring(0, $Text.Length - 1)
        }

        # A single-quoted literal escapes its own quote as \' , which JSON does not recognise.
        $Text = $Text.Replace("\'", "'").Replace('\"', '"')

        return ConvertFrom-OmadaAppPageVarJsonText -Text $Text
    }

    if ($FirstCharacter -eq "{" -or $FirstCharacter -eq "[") {
        return ConvertFrom-OmadaAppPageVarJsonText -Text $RawValue
    }

    return $RawValue
}

function ConvertFrom-OmadaAppPageVarJsonText {
    <#
    .SYNOPSIS
        Parses text as JSON when it can be, and returns the text unchanged when it cannot.

    .DESCRIPTION
        The "try, and keep the string on failure" rule in one place, used for both an unquoted object
        and a string that carries one. -AsHashtable so the result is a dictionary this module can walk
        and flatten rather than a PSCustomObject tree.

        PowerShell 7's ConvertFrom-Json is LENIENT about bare keys, which was measured rather than
        assumed: gridEquipmentDims ('{ counterHeight: 32, defaults: true }') parses into a dictionary
        instead of failing. A dictionary is strictly more useful to a caller than the raw text, so that
        is kept - but the catch stays, because text that is not an object at all must come back as
        itself.

        A successful parse is then walked by Expand-OmadaAppPageVarNestedJson, for the case one level
        of parsing cannot reach: settings that are JSON documents carried as escaped strings INSIDE
        another JSON object. uiHomePageActions and authElementPermissions both live in custSettings
        that way on a real tenant.

    .OUTPUTS
        The parsed value, or the original text.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    $Trimmed = $Text.Trim()
    if ($Trimmed.Length -eq 0 -or ($Trimmed[0] -ne "{" -and $Trimmed[0] -ne "[")) {
        return $Text
    }

    try {
        return (Expand-OmadaAppPageVarNestedJson -Value ($Trimmed | ConvertFrom-Json -AsHashtable -ErrorAction Stop) -Depth 0)
    }
    catch {
        # Not an object this parser can read. The string is the honest answer.
        return $Text
    }
}

function Expand-OmadaAppPageVarNestedJson {
    <#
    .SYNOPSIS
        Walks a parsed value and parses any string inside it that is itself a JSON document.

    .DESCRIPTION
        Issue #165. custSettings is JSON, and several of ITS values are JSON documents carried as
        escaped strings - uiHomePageActions and authElementPermissions on a real tenant. Parsing one
        level leaves those as text, so a caller asking for uiHomePageActions.processes would get a
        string back and have to parse it a second time.

        DEPTH-LIMITED rather than unbounded. The nesting is one or two levels in practice, and a
        malformed or hostile payload must not be able to make this recurse indefinitely - the same
        reason ConvertTo-RedactedLogString caps its own walk.

        A string that is not JSON is returned as itself, so this can be applied to every value without
        the caller deciding which ones to try.

    .PARAMETER Value
        The parsed value to walk.

    .PARAMETER Depth
        The current depth. Callers start at 0.

    .PARAMETER MaxDepth
        Where the walk stops and returns what it has.

    .OUTPUTS
        The value, with any nested JSON strings parsed.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [int]$Depth,

        [Parameter(Mandatory = $false)]
        [int]$MaxDepth = 6
    )

    # The one function in this file WITHOUT a tracer preamble. It recurses once per element of every
    # nested object and array - custSettings, uiHomePageActions, the language list - so a trace line
    # here would be thousands of lines per page, burying the calls that say what actually happened.
    # The call that starts the walk is traced (ConvertFrom-OmadaAppPageVarJsonText).

    if ($null -eq $Value -or $Depth -ge $MaxDepth) {
        return $Value
    }

    if ($Value -is [string]) {
        $Private:Trimmed = $Value.Trim()
        if ($Private:Trimmed.Length -eq 0 -or ($Private:Trimmed[0] -ne "{" -and $Private:Trimmed[0] -ne "[")) {
            return $Value
        }

        try {
            return (Expand-OmadaAppPageVarNestedJson -Value ($Private:Trimmed | ConvertFrom-Json -AsHashtable -ErrorAction Stop) -Depth ($Depth + 1) -MaxDepth $MaxDepth)
        }
        catch {
            return $Value
        }
    }

    if ($Value -is [System.Collections.IDictionary]) {
        # Keys snapshotted: the values are replaced in place as the walk goes.
        foreach ($Private:Key in @($Value.Keys)) {
            $Value[$Private:Key] = Expand-OmadaAppPageVarNestedJson -Value $Value[$Private:Key] -Depth ($Depth + 1) -MaxDepth $MaxDepth
        }

        return $Value
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $Private:Expanded = @()
        foreach ($Private:Item in $Value) {
            $Private:Expanded += , (Expand-OmadaAppPageVarNestedJson -Value $Private:Item -Depth ($Depth + 1) -MaxDepth $MaxDepth)
        }

        return , $Private:Expanded
    }

    return $Value
}
