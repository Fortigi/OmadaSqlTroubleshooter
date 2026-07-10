function Invoke-ExecuteScriptWithResultAsync {
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

                # Captured as a plain local (not $Script:-scoped) so GetNewClosure() below bakes
                # in the actual Dispatcher object - a $Script: reference would instead be a
                # dynamic-scope lookup that resolves to $null on the foreign thread this
                # continuation can run on, before Dispatcher.Invoke ever gets a chance to marshal
                # back to the UI thread.
                $CapturedDispatcher = $Script:MainForm.Definition.Dispatcher

                $WrappedScriptBlock = {
                    # Task continuations can run on a raw ThreadPool thread with no PowerShell
                    # runspace affinity, where calling a dot-sourced function throws
                    # CommandNotFoundException with nothing to catch it, crashing the whole
                    # process. Marshal onto the UI thread first so Get-ActiveTabSession et al.
                    # always run somewhere they can actually be resolved. BeginInvoke (not the
                    # blocking Invoke) - Invoke pumps the Windows message queue while it waits,
                    # and if that pump re-enters PowerShell (e.g. a WPF Loaded handler firing
                    # mid-pump), the engine throws PipelineStoppedException because it can't
                    # safely nest like that. Nothing here needs to block synchronously anyway.
                    $CapturedDispatcher.BeginInvoke([System.Action] {
                            # Capture whichever tab is actually active AT THE MOMENT this callback
                            # fires (not via Get-ActiveTabSession after the fact -
                            # Set-ActiveTabContext below would have already overwritten
                            # $Script:ActiveTabId to $TabSession's by then).
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
                        })
                }.GetNewClosure()

                $Task.GetAwaiter().OnCompleted($WrappedScriptBlock)
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
