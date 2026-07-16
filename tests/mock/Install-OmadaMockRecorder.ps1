#Requires -Version 7.0
<#
.SYNOPSIS
Record mode: run the app against a REAL tenant and tee each response into the fixture store, scrubbed
of PII. This is how the mock instance is refreshed from a live Omada.

.DESCRIPTION
Defines a top-level "function script:Invoke-OmadaRestMethod" that (when dot-sourced into the app's
module session by MockAppEntry.ps1) shadows OmadaWeb.PS's command for every caller - same mechanism as
the replay shim and tests/e2e/OmadaMocks.ps1. It calls the GENUINE OmadaWeb.PS implementation (so real
auth + HTTP still happen and the app behaves exactly as normal), then classifies the request with the
shared router and writes the response to the mapped fixture file after sanitizing it. The real result
is returned to the app unchanged, so a recording session is just a normal session with capture on.

Call Install-OmadaMockRecorder [-FixturesDir <dir>] [-ScrubGuids] to configure it. Requires
OmadaMockRouter.ps1 and Sanitize-OmadaFixture.ps1 (auto-loaded from this folder if absent).
#>

$script:OmadaMockRecordDir = $null
$script:OmadaMockRecordScrubGuids = $false

function Install-OmadaMockRecorder {
    [CmdletBinding()]
    param(
        [string]$FixturesDir,
        [switch]$ScrubGuids
    )
    if (-not (Get-Command -Name Get-OmadaMockRouteKey -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot "OmadaMockRouter.ps1")
    }
    if (-not (Get-Command -Name ConvertTo-SanitizedOmadaFixture -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot "Sanitize-OmadaFixture.ps1")
    }
    $script:OmadaMockRecordDir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    $script:OmadaMockRecordScrubGuids = [bool]$ScrubGuids
}

function Save-OmadaMockRecording {
    <# Persist one captured response to the fixture file mapped for $RouteKey. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RouteKey,
        $Response,
        [string]$FixturesDir,
        $ScrubMap,
        [switch]$ScrubGuids
    )
    $Dir = Get-OmadaMockFixturesDir -FixturesDir $FixturesDir
    $Manifest = Get-OmadaMockRoutes -FixturesDir $Dir
    $Route = $Manifest.routes.PSObject.Properties[$RouteKey]
    if ($null -eq $Route) {
        "Mock recorder: no fixture file mapped for route '$RouteKey' (skipped)." | Write-Host -ForegroundColor DarkYellow
        return
    }
    $Raw = if ($Response -is [string]) { $Response } else { $Response | ConvertTo-Json -Depth 25 }
    $Clean = ConvertTo-SanitizedOmadaFixture -Content $Raw -ScrubMap $ScrubMap -ScrubGuids:$ScrubGuids
    $FixturePath = Join-Path $Dir $Route.Value.file
    Set-Content -LiteralPath $FixturePath -Value $Clean -Encoding UTF8
    Clear-OmadaMockRoutesCache
    "Mock recorder: captured '$RouteKey' -> $($Route.Value.file)" | Write-Host -ForegroundColor DarkCyan
}

function script:Invoke-OmadaRestMethod {
    # OMADA_MOCK_RECORDER_MARKER - do not remove (used by the install sanity check).
    [CmdletBinding()]
    param(
        [string]$Uri,
        [string]$Method = "GET",
        $Body = $null,
        $AuthenticationType,
        $UseWebView2,
        $EntraApplicationIdUri,
        $EntraIdTenantId,
        $ForceAuthentication,
        $InPrivate,
        $SessionKey,
        $Credential,
        [Parameter(ValueFromRemainingArguments = $true)] $IgnoredRest
    )

    # Forward only the real parameters to the genuine OmadaWeb.PS implementation (real auth + HTTP).
    $Forward = @{}
    foreach ($Name in "Uri", "Method", "Body", "AuthenticationType", "UseWebView2", "EntraApplicationIdUri", "EntraIdTenantId", "ForceAuthentication", "InPrivate", "SessionKey", "Credential") {
        if ($PSBoundParameters.ContainsKey($Name)) { $Forward[$Name] = $PSBoundParameters[$Name] }
    }
    $Real = OmadaWeb.PS\Invoke-OmadaRestMethod @Forward

    try {
        $Key = Get-OmadaMockRouteKey -Path $Uri -Method $Method -Body $Body
        if ($null -ne $Key) {
            $ScrubMap = $null
            try {
                $TenantHost = if (![string]::IsNullOrWhiteSpace($Script:AppConfig.BaseUrl)) { ([uri]$Script:AppConfig.BaseUrl).Host } else { $null }
                $ScrubMap = New-OmadaScrubMap -TenantHost $TenantHost -UserName @($Script:AppConfig.IdentityUserName, $Script:AppConfig.UserName)
            }
            catch { $ScrubMap = $null }

            Save-OmadaMockRecording -RouteKey $Key -Response $Real -FixturesDir $script:OmadaMockRecordDir -ScrubMap $ScrubMap -ScrubGuids:$script:OmadaMockRecordScrubGuids
        }
    }
    catch {
        "Mock recorder failed to capture ${Uri}: $($_.Exception.Message)" | Write-Host -ForegroundColor DarkYellow
    }

    return $Real
}
