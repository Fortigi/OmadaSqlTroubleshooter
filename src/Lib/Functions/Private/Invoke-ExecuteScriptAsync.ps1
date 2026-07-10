function Invoke-ExecuteScriptAsync {
    <#
    .SYNOPSIS
    Executes a script in the active tab's WebView2/Monaco editor and invokes a callback when
    done. The pending task is stored on the originating tab (not a single shared global), and
    the callback is wrapped so it always runs with that same tab's context active - even if the
    user has switched to a different tab by the time it actually completes.
    #>
    [CmdLetBinding()]
    param(
        $ScriptToExecute,
        $OnCompletedScriptBlock
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:Webview.Object) {
            if ($Script:Webview.Object.IsLoaded) {
                $TabSession = Get-ActiveTabSession
                $Task = $Script:Webview.Object.CoreWebView2.ExecuteScriptAsync($ScriptToExecute)
                if ($null -ne $TabSession) {
                    $TabSession.PendingTask = $Task
                }
                $Script:Task = $Task

                # Neither Task.GetAwaiter().OnCompleted(scriptblock) nor DispatcherTimer.Tick
                # reliably preserve PowerShell's [Runspace]::DefaultRunspace (a [ThreadStatic]
                # property) for a scriptblock created via GetNewClosure() inside a function -
                # calling a dot-sourced function from one can throw CommandNotFoundException with
                # nothing able to catch it, crashing the whole process, even though built-in
                # cmdlets keep resolving fine (they don't depend on DefaultRunspace the same way).
                # Capture the runspace that's active here, where everything works, and explicitly
                # restore it as the very first thing the deferred callback does - before touching
                # any dot-sourced function.
                $CapturedRunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace

                $PollTimer = New-Object System.Windows.Threading.DispatcherTimer
                $PollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
                $PollTimer.Add_Tick({
                        if (-not $Task.IsCompleted) {
                            return
                        }
                        $PollTimer.Stop()

                        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $CapturedRunspace

                        # Capture whichever tab is actually active AT THE MOMENT this fires (not
                        # via Get-ActiveTabSession after the fact - Set-ActiveTabContext below
                        # would have already overwritten $Script:ActiveTabId to $TabSession's by
                        # then).
                        $PreviouslyActiveTab = Get-ActiveTabSession
                        try {
                            if ($null -ne $TabSession) {
                                Set-ActiveTabContext -TabSession $TabSession
                            }
                            & $OnCompletedScriptBlock
                        }
                        finally {
                            if ($null -ne $PreviouslyActiveTab) {
                                Set-ActiveTabContext -TabSession $PreviouslyActiveTab
                            }
                        }
                    }.GetNewClosure())
                $PollTimer.Start()
            }
            else {
                Write-LogOutput -Message "WebView2 is not loaded yet." -LogType DEBUG
            }
        }
        else {
            Write-LogOutput -Message "WebView2 is not initialized." -LogType ERROR
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
