#Requires -Version 7.0
<#
.SYNOPSIS
Replay transport shim: make the app talk to the mock server instead of a real Omada tenant.

.DESCRIPTION
The single seam between the app and the network is OmadaWeb.PS's Invoke-OmadaRestMethod, which does
auth (WebView2/Browser/OAuth) + HTTP. This file defines a "function script:Invoke-OmadaRestMethod"
override AT TOP LEVEL so that, when dot-sourced from within the app's module session (as MockAppEntry.ps1
does), it lands in the module's script scope and shadows the imported OmadaWeb.PS command for every
caller - the exact mechanism tests/e2e/OmadaMocks.ps1 relies on. Everything ABOVE the OmadaWeb.PS
boundary (Invoke-OmadaPSWebRequestWrapper, URL building, response parsing, the whole UI) runs unchanged.

Call Install-OmadaMockTransport -MockBaseUrl <url> to point the shim at the running mock server. The
shim reads $script:OmadaMockBaseUrl at call time, so setting it after dot-sourcing is fine.
#>

# Marker string asserted by MockAppEntry.ps1 to confirm the shadow actually took effect.
$script:OmadaMockBaseUrl = $null

function Install-OmadaMockTransport {
    [CmdletBinding()]
    param([string]$MockBaseUrl)
    $script:OmadaMockBaseUrl = $MockBaseUrl
}

function script:Invoke-OmadaRestMethod {
    # OMADA_MOCK_TRANSPORT_MARKER - do not remove (used by the install sanity check).
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

    $TargetUri = [string]$Uri
    # Rewrite the host to the mock so any tenant URL the app built lands on the mock instance.
    if (![string]::IsNullOrWhiteSpace($script:OmadaMockBaseUrl) -and $TargetUri -match '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+(/.*)$') {
        $TargetUri = "{0}{1}" -f $script:OmadaMockBaseUrl.TrimEnd("/"), $Matches[1]
    }

    $HttpMethod = if ([string]::IsNullOrWhiteSpace($Method)) { "GET" } else { $Method.ToUpperInvariant() }
    $IrmParams = @{
        Uri     = $TargetUri
        Method  = $HttpMethod
        NoProxy = $true   # the mock is on localhost; never route it through a configured proxy
    }
    if ($HttpMethod -in @("POST", "PUT", "PATCH") -and $null -ne $Body) {
        $IrmParams.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        $IrmParams.ContentType = "application/json; charset=utf-8"
    }

    return Invoke-RestMethod @IrmParams
}
