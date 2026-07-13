function Set-ActiveTabContext {
    <#
    .SYNOPSIS
    Repoints the "current tab" globals ($Script:MainForm.Elements, $Script:RunTimeData,
    $Script:WebView, $Script:AppConfig, $Script:ConnectionStatus, $Script:Task,
    $Script:CurrentUrl) to the given tab session, saving scalar state back onto the outgoing
    tab first. This is the single
    mechanism used both for real tab switches (TabControlSessions.SelectionChanged) and for
    temporarily "stepping into" a tab from an async completion callback that may fire while a
    different tab is on screen.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        # Logging the full $PSBoundParameters here would dump the entire $TabSession object graph
        # (WPF elements, AppConfig) into the trace log - log a stable identifier instead.
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ("TabSession={0} ({1})" -f $TabSession.Id, $TabSession.DisplayName)))

        if ($null -ne $Script:ActiveTabId -and $Script:ActiveTabId -ne $TabSession.Id) {
            $Outgoing = $Script:Tabs | Where-Object { $_.Id -eq $Script:ActiveTabId } | Select-Object -First 1
            if ($null -ne $Outgoing) {
                $Outgoing.ConnectionStatus = $Script:ConnectionStatus
                $Outgoing.PendingTask = $Script:Task
                $Outgoing.CurrentUrl = $Script:CurrentUrl
            }
        }

        $Script:MainForm.Elements = $TabSession.Elements
        $Script:RunTimeData = $TabSession.RunTimeData
        $Script:WebView = $TabSession.WebView
        $Script:AppConfig = $TabSession.AppConfig
        $Script:ConnectionStatus = $TabSession.ConnectionStatus
        $Script:Task = $TabSession.PendingTask
        $Script:CurrentUrl = $TabSession.CurrentUrl
        $Script:ActiveTabId = $TabSession.Id

        Initialize-UiComponents
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
