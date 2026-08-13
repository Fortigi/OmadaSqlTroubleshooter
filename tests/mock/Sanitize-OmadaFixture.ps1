#Requires -Version 7.0
<#
.SYNOPSIS
PII scrubbing for recorded Omada fixtures, so captured example data is safe to commit.

.DESCRIPTION
The recorder (Install-OmadaMockRecorder.ps1) captures real responses from a live tenant. Before those
land in fixtures/ they pass through here: the tenant host and known usernames are replaced with stable
placeholders, and emails (and optionally GUIDs) are generically scrubbed. This is what removes the
manual-blurring step that today's README screenshot needs.

Dot-source to get New-OmadaScrubMap and ConvertTo-SanitizedOmadaFixture; nothing runs on load.
#>

function New-OmadaScrubMap {
    <#
    .SYNOPSIS
    Build an ordered literal-replacement map from live connection identity. Longer strings first so a
    full "host/path" is replaced before a bare host fragment.
    #>
    [CmdletBinding()]
    param(
        [string]$TenantHost,
        [string[]]$UserName,
        [hashtable]$Extra
    )
    $Map = [ordered]@{}
    if (![string]::IsNullOrWhiteSpace($TenantHost)) { $Map[$TenantHost] = "tenant.omada.cloud" }
    foreach ($U in @($UserName)) {
        if (![string]::IsNullOrWhiteSpace($U)) { $Map[$U] = "MOCK\serviceaccount" }
    }
    if ($null -ne $Extra) {
        foreach ($Key in $Extra.Keys) { $Map[[string]$Key] = [string]$Extra[$Key] }
    }
    return $Map
}

function ConvertTo-JsonEscapedFragment {
    <#
    Return $Text as it would appear INSIDE a JSON string value (backslashes doubled, quotes escaped),
    without the surrounding quotes. Used so the scrubber matches values in already-serialized JSON.
    #>
    [CmdletBinding()]
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $Json = $Text | ConvertTo-Json -Compress
    return $Json.Substring(1, $Json.Length - 2)
}

function ConvertTo-SanitizedOmadaFixture {
    <#
    .SYNOPSIS
    Return $Content with the scrub map applied plus generic email (and optional GUID) redaction.

    .PARAMETER ScrubGuids
    Replace each distinct GUID with a stable sequential placeholder (preserves row distinctness while
    removing real identifiers). Off by default - GUIDs are low-sensitivity and needed for realistic rows.
    #>
    [CmdletBinding()]
    param(
        [string]$Content,
        $ScrubMap,
        [switch]$ScrubGuids
    )

    $Out = [string]$Content
    if ($null -ne $ScrubMap) {
        # Build the replacement set. For every entry we scrub BOTH the raw value and its JSON-escaped
        # form: the recorder serializes the response with ConvertTo-Json before sanitizing, so a
        # domain-qualified account like "ACME\m.jansen" appears in the text as "ACME\\m.jansen" and a
        # raw literal replace would silently miss it - leaking exactly the PII this is meant to remove.
        $Replacements = [System.Collections.Generic.List[object]]::new()
        foreach ($Key in $ScrubMap.Keys) {
            $RawFrom = [string]$Key
            if ([string]::IsNullOrEmpty($RawFrom)) { continue }
            $RawTo = [string]$ScrubMap[$Key]
            $Replacements.Add([pscustomobject]@{ From = $RawFrom; To = $RawTo })

            $EscapedFrom = ConvertTo-JsonEscapedFragment -Text $RawFrom
            if ($EscapedFrom -cne $RawFrom) {
                $Replacements.Add([pscustomobject]@{ From = $EscapedFrom; To = (ConvertTo-JsonEscapedFragment -Text $RawTo) })
            }
        }

        # Longest match first. Applying in insertion order lets a shorter entry rewrite the inside of a
        # longer one (replacing the bare host first leaves "host/path" unmatchable), which would
        # silently leave the more specific PII behind.
        foreach ($Replacement in ($Replacements | Sort-Object -Property { $_.From.Length } -Descending)) {
            $Out = $Out.Replace($Replacement.From, $Replacement.To)
        }
    }

    # Emails -> a single placeholder.
    $Out = [regex]::Replace($Out, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', 'user@example.com')

    if ($ScrubGuids) {
        $GuidMap = @{}
        $Counter = [ref]0
        $Evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
            param($M)
            $G = $M.Value.ToLowerInvariant()
            if (-not $GuidMap.ContainsKey($G)) {
                $GuidMap[$G] = "00000000-0000-0000-0000-{0:d12}" -f $Counter.Value
                $Counter.Value++
            }
            return $GuidMap[$G]
        }
        $Out = [regex]::Replace($Out, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', $Evaluator)
    }

    return $Out
}
