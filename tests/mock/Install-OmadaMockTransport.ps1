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
    $RequestParams = @{
        Uri     = $TargetUri
        Method  = $HttpMethod
        NoProxy = $true   # the mock is on localhost; never route it through a configured proxy
    }
    if ($HttpMethod -in @("POST", "PUT", "PATCH") -and $null -ne $Body) {
        $RequestParams.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        $RequestParams.ContentType = "application/json; charset=utf-8"
    }

    # Deliberately Invoke-WebRequest, NOT Invoke-RestMethod: the latter auto-deserializes by content
    # type, which turns the dataobjdlg.aspx HTML into an [XmlDocument]. Update-DataConnectionList feeds
    # that result to Get-DataConnectionOptionList -Html ([string]), where an XmlDocument stringifies to
    # "System.Xml.XmlDocument" and the <option> regex matches nothing - i.e. no data connections, so no
    # schema. Branching on the content type here reproduces what OmadaWeb.PS hands back: deserialized
    # objects for JSON, the raw markup for HTML.
    $Response = Invoke-WebRequest @RequestParams
    $ResponseContentType = [string]$Response.Headers["Content-Type"]

    if ($ResponseContentType -like "*json*") {
        if ([string]::IsNullOrWhiteSpace($Response.Content)) { return $null }
        return ($Response.Content | ConvertFrom-Json)
    }

    return $Response.Content
}
