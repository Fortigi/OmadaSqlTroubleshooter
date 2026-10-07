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

        # Whether this is a real switch or a completion "stepping into" the tab that is already on
        # screen. The two must not be treated alike - see the scalars below.
        $Private:SteppingIntoActiveTab = ($null -ne $Script:ActiveTabId -and $Script:ActiveTabId -eq $TabSession.Id)

        # The object references are the same objects for the same tab, so these are idempotent.
        $Script:MainForm.Elements = $TabSession.Elements
        $Script:RunTimeData = $TabSession.RunTimeData
        $Script:WebView = $TabSession.WebView
        $Script:AppConfig = $TabSession.AppConfig

        # THE SCALARS ARE ONLY RESTORED FOR A REAL SWITCH, and the asymmetry at the top of this
        # function is the reason (issue #165). The save there is skipped when the incoming tab is
        # already the active one - so restoring here would overwrite a LIVE value with a stored copy
        # that was never updated.
        #
        # $Script:Task is the one that bites. Invoke-ExecuteScriptAsync and
        # Invoke-ExecuteScriptWithResultAsync write $TabSession.PendingTask when they START an editor
        # task, and New-TabSession seeds it $null. A background completion that stepped into the
        # ACTIVE tab while a newer editor task was in flight therefore replaced $Script:Task with a
        # stale $null and the task was lost - silently, because an editor read that never produces a
        # result is indistinguishable from one that was never asked for. What it looked like from the
        # outside: validation markers that were simply never pushed.
        #
        # Latent before #165 and only reachable with enough completions to land inside that window;
        # the schema fan-out produces them, which is how it was found.
        if (-not $Private:SteppingIntoActiveTab) {
            $Script:ConnectionStatus = $TabSession.ConnectionStatus
            $Script:Task = $TabSession.PendingTask
            $Script:CurrentUrl = $TabSession.CurrentUrl
        }

        $Script:ActiveTabId = $TabSession.Id

        Initialize-UiComponents
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
