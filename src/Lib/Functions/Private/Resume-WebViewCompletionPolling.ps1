function Resume-WebViewCompletionPolling {
    <#
    .SYNOPSIS
    Restarts $Script:WebViewCompletionPollTimer after a blocking, modal dialog closes. Pair with
    Suspend-WebViewCompletionPolling in a try/finally around every ShowDialog()/MessageBox.Show()
    call.
    #>
    [CmdLetBinding()]
    param()
    if ($null -ne $Script:WebViewCompletionPollTimer) {
        $Script:WebViewCompletionPollTimer.Start()
    }
}
