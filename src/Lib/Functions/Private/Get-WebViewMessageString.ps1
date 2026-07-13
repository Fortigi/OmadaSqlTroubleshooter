function Get-WebViewMessageString {
    <#
    .SYNOPSIS
    Returns the raw string of a WebView2 web message, tolerating both string- and object-posted
    messages.

    .DESCRIPTION
    The Monaco editor posts its messages as objects (window.chrome.webview.postMessage({ type: ... })).
    For an object-posted message CoreWebView2's TryGetWebMessageAsString() throws
    "Value does not fall within the expected range." - which flooded the log on every keystroke via
    the 'contentChanged' message. Fall back to WebMessageAsJson (which is always populated) so the
    JSON body is returned for both object- and string-posted messages.
    #>
    [CmdLetBinding()]
    param(
        $MessageEventArgs
    )

    if ($null -eq $MessageEventArgs) {
        return $null
    }

    try {
        return $MessageEventArgs.TryGetWebMessageAsString()
    }
    catch {
        return $MessageEventArgs.WebMessageAsJson
    }
}
