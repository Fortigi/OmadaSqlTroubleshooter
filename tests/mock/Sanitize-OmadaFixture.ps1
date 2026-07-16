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
        foreach ($Key in $ScrubMap.Keys) {
            $K = [string]$Key
            if ([string]::IsNullOrEmpty($K)) { continue }
            $Out = $Out.Replace($K, [string]$ScrubMap[$Key])
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
