function Suspend-WebViewCompletionPolling {
    <#
    .SYNOPSIS
    Stops $Script:WebViewCompletionPollTimer for the duration of a blocking, modal dialog
    (ShowDialog()/MessageBox.Show()).

    .NOTES
    A modal dialog pumps this thread's message queue while it blocks, including WM_TIMER, so the
    poll timer's Tick can fire reentrantly nested inside it - invoking PowerShell script as a
    second, nested pipeline on the same runspace while this one is paused mid-statement inside a
    native call. That corrupts command resolution for the reentrant invocation (confirmed via
    CliXML: even Write-LogOutput itself became unresolvable when invoked this way). Call this
    immediately before showing any blocking dialog, and Resume-WebViewCompletionPolling
    afterward (in a finally), so the timer simply cannot fire while blocked.
    #>
    [CmdLetBinding()]
    param()
    if ($null -ne $Script:WebViewCompletionPollTimer) {
        $Script:WebViewCompletionPollTimer.Stop()
    }
}
