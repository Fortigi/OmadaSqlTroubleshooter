#Requires -Version 7.0
<#
.SYNOPSIS
Routing brain for the mock Omada instance. Maps an incoming (path, method, body) to a logical route
key and resolves that key to a fixture response.

.DESCRIPTION
This is the single source of truth for "which Omada endpoint is this?" - shared by the HTTP server
(Start-OmadaMockServer.ps1), the replay transport shim (Install-OmadaMockTransport.ps1) and the
recorder (Install-OmadaMockRecorder.ps1), so a request is classified identically whether it is being
served or captured.

It generalizes tests/e2e/Fixtures.ps1::Resolve-E2EFixture: same path/method/dataType matching, but
responses come from files under fixtures/ (see routes.json) instead of inline literals, and the body
is returned as a raw string for the app's own parser (Invoke-RestMethod / the app) to deserialize.

Dot-source this file to get the functions; nothing runs on load.
#>

$script:OmadaMockRoutesCache = @{}

function Get-OmadaMockFixturesDir {
    <# Default fixtures directory (sibling 'fixtures' folder), overridable by callers. #>
    [CmdletBinding()]
    param([string]$FixturesDir)
    if (![string]::IsNullOrWhiteSpace($FixturesDir)) { return (Resolve-Path -LiteralPath $FixturesDir).Path }
    return (Join-Path $PSScriptRoot "fixtures")
}

function Get-OmadaMockRoutes {
    <# Load (and cache) routes.json for a fixtures directory. #>
    [CmdletBinding()]
    param([string]$FixturesDir)
    $Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    if (-not $script:OmadaMockRoutesCache.ContainsKey($Dir)) {
        $ManifestPath = Join-Path $Dir "routes.json"
        if (-not (Test-Path -LiteralPath $ManifestPath)) {
            throw "Mock routes manifest not found: $ManifestPath"
        }
        $script:OmadaMockRoutesCache[$Dir] = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    }
    return $script:OmadaMockRoutesCache[$Dir]
}

function Clear-OmadaMockRoutesCache {
    <# Drop the routes.json cache so freshly recorded/edited manifests are picked up. #>
    [CmdletBinding()]
    param()
    $script:OmadaMockRoutesCache = @{}
}

function Get-OmadaMockDataType {
    <#
    Extract the GetPagingData 'dataType' discriminator from a request body. Accepts the raw JSON
    string (HTTP server path), a hashtable/ordered dictionary (the app's RestMethodParam.Body, used
    by the recorder) or a PSCustomObject.
    #>
    [CmdletBinding()]
    param($Body)
    if ($null -eq $Body) { return $null }
    if ($Body -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Body)) { return $null }
        try { $Parsed = $Body | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
        return $Parsed.dataType
    }
    if ($Body -is [System.Collections.IDictionary]) {
        if ($Body.Contains("dataType")) { return [string]$Body["dataType"] }
        return $null
    }
    $Prop = $Body.PSObject.Properties["dataType"]
    if ($null -ne $Prop) { return [string]$Prop.Value }
    return $null
}

function Get-OmadaMockRouteKey {
    <#
    .SYNOPSIS
    Classify an Omada request into a logical route key (see routes.json). Returns $null when no known
    endpoint matches (the caller then uses the manifest fallback).

    .PARAMETER Path
    The request path or full URI. Host/scheme are stripped; matching is case-insensitive and tolerant
    of the app's URL-casing variance (jQGrid/JQGrid, WebService/webservice).
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Method,
        $Body
    )

    $P = [string]$Path
    if ($P -match '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+(/.*)$') { $P = $Matches[1] }
    $Lower = $P.ToLowerInvariant()
    $HttpMethod = ([string]$Method).ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($HttpMethod)) { $HttpMethod = "GET" }

    # --- ASMX web services -------------------------------------------------------------------------
    if ($Lower -like "*syntaxhighlighting.asmx/getsqlschema*") { return "schema" }
    if ($Lower -like "*dataobjectwebservice.asmx/undeletedataobject*") { return "undelete" }
    if ($Lower -like "*getpagingdata*") {
        switch (([string](Get-OmadaMockDataType -Body $Body)).ToLowerInvariant()) {
            "views"             { return "paging.views" }
            "dataobjects"       { return "paging.dataobjects" }
            "sqldataproducer"   { return "paging.sqldataproducer" }
            "dataobjecthistory" { return "paging.dataobjecthistory" }
            default             { return $null }
        }
    }

    # --- Data connection dropdown HTML -------------------------------------------------------------
    if ($Lower -like "*dataobjdlg.aspx*") { return "dataconnections" }

    # --- OData C_P_SQLTROUBLESHOOTING ---------------------------------------------------------------
    if ($Lower -like "*c_p_sqltroubleshooting*") {
        # A parenthesised key segment => operating on a single object by id.
        if ($Lower -match "c_p_sqltroubleshooting\(") {
            switch ($HttpMethod) {
                "GET"    { return "queryobject" }
                "DELETE" { return "deletequery" }
                default  { return "updatequery" }   # PUT / PATCH / POST on (id) => update
            }
        }
        if ($HttpMethod -eq "POST") { return "createquery" }
        if ($Lower -like "*name eq*" -or $Lower -like "*name%20eq*") { return "namecheck" }
        if ($Lower -like "*orderby*") { return "querylist" }
        return "probe"
    }

    return $null
}

function Resolve-OmadaMockResponse {
    <#
    .SYNOPSIS
    Resolve a request to a concrete mock response read from the fixture store.

    .OUTPUTS
    Hashtable @{ StatusCode = <int>; ContentType = <string>; Body = <string>; RouteKey = <string>;
    DelayMs = <int> }.

    .NOTES
    DelayMs comes from the route's optional "delayMs" field in routes.json and is how a test asks the
    mock to answer slowly - the server sleeps for it before writing the response, so the delay is felt
    on a real socket by a real Invoke-RestMethod rather than being faked inside a shim. Routes without
    the field resolve to 0. A live per-route override (Set-OmadaMockRouteDelay) takes precedence and is
    what a test should normally use; the manifest field exists for fixtures that are inherently slow.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Method,
        $Body,
        [string]$FixturesDir
    )

    $Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    $Manifest = Get-OmadaMockRoutes -FixturesDir $Dir
    $Key = Get-OmadaMockRouteKey -Path $Path -Method $Method -Body $Body

    if ($null -ne $Key) {
        $Route = $Manifest.routes.PSObject.Properties[$Key]
        if ($null -ne $Route) {
            $FixturePath = Join-Path $Dir $Route.Value.file
            if (Test-Path -LiteralPath $FixturePath) {
                return @{
                    StatusCode  = [int]$Route.Value.status
                    ContentType = [string]$Route.Value.contentType
                    Body        = (Get-Content -LiteralPath $FixturePath -Raw)
                    RouteKey    = $Key
                    DelayMs     = (Get-OmadaMockRouteDelayMs -Route $Route.Value)
                }
            }
        }
    }

    $Fallback = $Manifest.fallback
    return @{
        StatusCode  = [int]$Fallback.status
        ContentType = [string]$Fallback.contentType
        Body        = [string]$Fallback.inlineBody
        RouteKey    = ($null -ne $Key ? $Key : "fallback")
        DelayMs     = (Get-OmadaMockRouteDelayMs -Route $Fallback)
    }
}

function Get-OmadaMockRouteDelayMs {
    <#
    Read a route entry's optional "delayMs". Absent, null or non-numeric all mean "no delay" - a
    manifest without the field must keep behaving exactly as it did before the field existed.
    #>
    [CmdletBinding()]
    param($Route)
    if ($null -eq $Route) { return 0 }
    $Property = $Route.PSObject.Properties["delayMs"]
    if ($null -eq $Property -or $null -eq $Property.Value) { return 0 }
    $Parsed = 0
    if (-not [int]::TryParse([string]$Property.Value, [ref]$Parsed)) { return 0 }
    if ($Parsed -lt 0) { return 0 }
    return $Parsed
}
