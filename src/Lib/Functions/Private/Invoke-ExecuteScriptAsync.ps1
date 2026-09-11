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
        # THE PAYLOAD IS TRACED BY SHAPE, NEVER BY CONTENT. The preamble every other function here
        # opens with writes ConvertTo-RedactedLogString of its bound parameters, and this function's
        # parameter is a whole JavaScript payload made out of the user's and the tenant's own text:
        #
        #   setEditorValue('...')    the query, verbatim
        #   setSchema({...})         every table and column name in the customer's database
        #   setDiagnostics([...])    the diagnostic messages, which quote the script - the parser's
        #                            "Incorrect syntax near 'Person'.", the schema pass naming a table
        #                            and a column, a rule quoting the user's own alias
        #
        # Redaction does not help: ConvertTo-RedactedLogString masks credentials and result data, not
        # identifiers lifted out of a query or a schema. So the trace records the call and the size
        # and stops there - which is what issue #61 section 5 and acceptance criteria 8 and A10
        # require, and what the deliberate absence of a preamble everywhere else on the validation
        # path exists to protect.
        #
        # Done here rather than at the call sites on purpose. A per-caller opt-out only protects the
        # callers who remember it, and the next one to push editor content would leak by omission.
        #
        # The length is kept because it is the part that is actually useful when debugging this seam:
        # an empty push, a truncated one, or a schema that grew unexpectedly all show up in it, and
        # none of them needs the text.
        $Private:TracedParameter = [Ordered]@{
            ScriptToExecute        = "<{0} characters>" -f ([string]$ScriptToExecute).Length
            OnCompletedScriptBlock = if ($null -eq $OnCompletedScriptBlock) { "<none>" } else { "<scriptblock>" }
        }
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $Private:TracedParameter -MaxDepth 1)))

        if ($null -ne $Script:Webview.Object) {
            # CoreWebView2 must be checked too, not just IsLoaded: while a tab is being torn down
            # (e.g. Close All disposing tabs), a focus-driven editor push can land on a WebView2
            # control that is still IsLoaded but whose CoreWebView2 has already been disposed/nulled
            # - calling ExecuteScriptAsync on that null would throw.
            if ($Script:Webview.Object.IsLoaded -and $null -ne $Script:Webview.Object.CoreWebView2) {
                $TabSession = Get-ActiveTabSession
                $Task = $Script:Webview.Object.CoreWebView2.ExecuteScriptAsync($ScriptToExecute)
                if ($null -ne $TabSession) {
                    $TabSession.PendingTask = $Task
                }
                $Script:Task = $Task

                # A scriptblock created inside this function (via GetNewClosure(), a Task
                # continuation, or a DispatcherTimer created here) does not reliably resolve
                # dot-sourced functions once invoked later by .NET's own dispatch machinery -
                # CommandNotFoundException, uncaught. Enqueue plain data instead; the single,
                # top-level WebViewCompletionPollTimer in MainForm.Definition.ps1 is what
                # actually calls Set-ActiveTabContext and invokes $OnCompletedScriptBlock, from a
                # call frame that has always reliably resolved functions.
                $Script:PendingWebViewCompletions.Add([PSCustomObject]@{
                        Task                   = $Task
                        TabSession             = $TabSession
                        OnCompletedScriptBlock = $OnCompletedScriptBlock
                    })
            }
            else {
                Write-LogOutput -Message "WebView2 is not ready (not loaded or CoreWebView2 unavailable); skipping editor script." -LogType DEBUG
            }
        }
        else {
            # Reaching here means the active tab's WebView2 control has not been created yet
            # (New-TabSession calls Set-SqlConnectionState -Status $false - which clears the
            # editor - before Initialize-WebViewForTab runs). There is no editor to push to yet;
            # Initialize-WebViewForTab sets the editor value once WebView2 is ready. This is an
            # expected transient during tab startup, not an error - same class as the "not loaded
            # yet" case above.
            Write-LogOutput -Message "WebView2 is not initialized yet; skipping editor script." -LogType DEBUG
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
