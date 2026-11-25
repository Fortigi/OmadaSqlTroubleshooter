function Stop-ApplicationTimer {
    <#
    .SYNOPSIS
        Stops every DispatcherTimer the application started, and lets go of them.

    .DESCRIPTION
        The timers belong to the thread's Dispatcher, not to the main window, and the Dispatcher
        outlives a run: Invoke-OmadaSqlTroubleshooter can be started again in the same PowerShell
        session, on the same thread. A timer that is not stopped keeps ticking whenever that thread
        pumps messages again - in the next run, next to the new run's own timers, acting on the new
        run's state. The 50 ms completion poll timer, for one, drives the session keep-alive pings, so
        an old one doubles them.

        Called when a run ends and again before a run starts, so a run that ended without reaching its
        clean-up (an exception, a terminated host) does not leave its timers to the next one.

        $Script:SqlSchemaFilterTimer is created by the schema window; it is stopped here too, because
        that window can be the last thing a run had open.

    .OUTPUTS
        [int] How many timers were stopped.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $Private:Stopped = 0
    foreach ($Private:Name in @("WebViewCompletionPollTimer", "SqlValidationDebounceTimer", "SqlSchemaFilterTimer", "E2EWatchdog")) {
        $Private:Timer = Get-Variable -Scope Script -Name $Private:Name -ValueOnly -ErrorAction SilentlyContinue
        if ($null -eq $Private:Timer) {
            continue
        }

        try {
            $Private:Timer.Stop()
            $Private:Stopped++
        }
        catch {
            "Could not stop timer {0}: {1}" -f $Private:Name, $_.Exception.Message | Write-LogOutput -LogType DEBUG
        }
        Set-Variable -Scope Script -Name $Private:Name -Value $null
    }

    "Application timers stopped: {0}" -f $Private:Stopped | Write-LogOutput -LogType DEBUG
    return $Private:Stopped
}
