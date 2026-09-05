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

# Every request the app makes reaches the mock instance through the shim below, so recording them
# here gives a test an exact, complete picture of what did (or did not) hit the tenant. Tests that
# assert a code path performs NO authenticated request read this log.
# Synchronized, and an ArrayList rather than a List[object], because issue #40 lets requests run in
# worker runspaces: the workers append to this same instance so Get-OmadaMockRequestLog in the app's
# runspace sees every request, whichever thread made it.
$script:OmadaMockRequestLog = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

function Install-OmadaMockTransport {
    [CmdletBinding()]
    param([string]$MockBaseUrl)
    $script:OmadaMockBaseUrl = $MockBaseUrl

    # Issue #40: requests now also run in worker runspaces, which have their own copy of OmadaWeb.PS
    # and would therefore call the REAL Invoke-OmadaRestMethod - reaching past this shim to whatever
    # tenant URL the app built. Registering this file and its configuration on the two
    # $Script:OmadaRequestWorkerTransport* variables tells Start-OmadaBackgroundRequest to dot-source
    # it in the worker and call Initialize-OmadaRequestWorkerTransport there, so the shim covers the
    # background path exactly as it covers the inline one.
    #
    # The request log is handed over as a synchronized list rather than each runspace keeping its
    # own, so Get-OmadaMockRequestLog in the app's runspace still sees every request - including the
    # ones a worker made. Tests that assert a code path issued (or did not issue) a call depend on
    # that being one list.
    $Script:OmadaRequestWorkerTransportPath = $PSCommandPath
    $Script:OmadaRequestWorkerTransportContext = @{
        MockBaseUrl = $MockBaseUrl
        RequestLog  = $script:OmadaMockRequestLog
    }
}

function Initialize-OmadaRequestWorkerTransport {
    <#
    .SYNOPSIS
    Called inside a background worker runspace, after this file has been dot-sourced there, to point
    the worker's shim at the same mock server and the same shared request log as the app's runspace.

    .DESCRIPTION
    The name is the contract Start-OmadaBackgroundRequest looks for; it calls this only when the
    function exists, so a normal (non-mock) run has no idea any of this is here.
    #>
    [CmdletBinding()]
    param($Context)
    if ($null -eq $Context) { return }
    $script:OmadaMockBaseUrl = $Context.MockBaseUrl
    if ($null -ne $Context.RequestLog) {
        $script:OmadaMockRequestLog = $Context.RequestLog
    }
}

function Clear-OmadaMockRequestLog {
    [CmdletBinding()]
    param()
    $script:OmadaMockRequestLog.Clear()
}

function Get-OmadaMockRequestLog {
    [CmdletBinding()]
    param(
        [string]$UriLike = "*",
        [string]$MethodLike = "*"
    )
    return @($script:OmadaMockRequestLog | Where-Object { $_.Uri -like $UriLike -and $_.Method -like $MethodLike })
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
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(ValueFromRemainingArguments = $true)] $IgnoredRest
    )

    $TargetUri = [string]$Uri
    # Rewrite the host to the mock so any tenant URL the app built lands on the mock instance.
    if (![string]::IsNullOrWhiteSpace($script:OmadaMockBaseUrl) -and $TargetUri -match '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+(/.*)$') {
        $TargetUri = "{0}{1}" -f $script:OmadaMockBaseUrl.TrimEnd("/"), $Matches[1]
    }

    $HttpMethod = if ([string]::IsNullOrWhiteSpace($Method)) { "GET" } else { $Method.ToUpperInvariant() }

    # Recorded before the call goes out, so a request that fails still counts as "the app talked to
    # the tenant" - which is exactly what a zero-request assertion has to catch.
    # [void]: ArrayList.Add returns the new index, which would otherwise land in this function's
    # output stream and be returned to the caller alongside the actual response.
    [void]$script:OmadaMockRequestLog.Add([PSCustomObject]@{
            Uri    = $TargetUri
            Method = $HttpMethod
            Body   = $Body
        })

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

