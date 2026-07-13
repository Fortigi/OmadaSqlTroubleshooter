function Get-TabSessionByWebViewSender {
    <#
    .SYNOPSIS
    Finds the tab session that owns a given WebView2/CoreWebView2 event sender.

    .DESCRIPTION
    WebView2 event handlers (PreviewKeyDown, WebMessageReceived, NavigationCompleted) must run as
    plain scriptblocks - NOT .GetNewClosure() blocks - so that they can resolve the module's
    dot-sourced private functions when .NET invokes them later (a GetNewClosure() block runs in a
    detached dynamic module whose scope does not include this module's private functions, which
    throws CommandNotFoundException). A plain block cannot capture $TabSession by reference, so it
    recovers the owning tab here from the event sender instead: the sender is either the tab's
    WebView2 control (PreviewKeyDown/NavigationCompleted) or its CoreWebView2 (WebMessageReceived).
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Sender
    )
    try {
        foreach ($Tab in $Script:Tabs) {
            $WebViewObject = $Tab.WebView.Object
            if ($null -eq $WebViewObject) {
                continue
            }
            if ($WebViewObject -eq $Sender) {
                return $Tab
            }
            if ($null -ne $WebViewObject.CoreWebView2 -and $WebViewObject.CoreWebView2 -eq $Sender) {
                return $Tab
            }
        }
        return $null
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        return $null
    }
}
