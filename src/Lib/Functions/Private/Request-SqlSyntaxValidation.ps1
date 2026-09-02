function Request-SqlSyntaxValidation {
    <#
    .SYNOPSIS
        Schedules a debounced syntax validation for a tab whose editor content has changed.

    .DESCRIPTION
        Restarting a DispatcherTimer on every change is what makes the pass idle-triggered rather
        than keystroke-triggered: while the user keeps typing the timer keeps being pushed forward,
        and the parse happens once, after ValidationDebounceMilliseconds of quiet.

        The timer itself lives at the top level of MainForm.Definition.ps1, next to the WebView2
        completion poll timer and for the same reason - a DispatcherTimer whose Tick handler is
        created inside a function cannot resolve this module's dot-sourced private functions when
        .NET later invokes it.

    .PARAMETER TabSession
        The tab whose editor changed. Recorded so the Tick handler validates that tab's content even
        if the user has switched tabs in the meantime.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $TabSession
    )

    # No tracer preamble: called on every keystroke.

    try {
        if ($null -eq $Script:SqlValidationDebounceTimer) {
            return
        }

        $Setting = Get-SqlValidationSetting
        if (-not $Setting.Enabled) {
            return
        }

        if ($null -ne $TabSession) {
            $Script:SqlValidationPendingTabId = $TabSession.Id
        }

        $Script:SqlValidationDebounceTimer.Stop()
        $Script:SqlValidationDebounceTimer.Interval = [TimeSpan]::FromMilliseconds($Setting.DebounceMilliseconds)
        $Script:SqlValidationDebounceTimer.Start()
    }
    catch {
        "Scheduling syntax validation failed." | Write-LogOutput -LogType DEBUG
    }
}
