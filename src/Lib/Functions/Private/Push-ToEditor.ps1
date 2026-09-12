function Push-ToEditor {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$ScriptToExecute
    )
    try {
        # THE PAYLOAD IS TRACED BY SHAPE, NEVER BY CONTENT (issue #111). $ScriptToExecute is a
        # JavaScript payload built out of the user's own text: Set-EditorValue interpolates the saved
        # query straight into "window.setEditorValue('...')", so the ordinary act of opening a query
        # wrote that query into the trace - and the log window has an Export Log File button.
        #
        # Redaction is not the defence: ConvertTo-RedactedLogString masks credentials, tokens and
        # result data, not statement text or identifiers taken from a query. Nothing tells it that
        # this string is one.
        #
        # $MyInvocation.Statement goes too. It is the SOURCE TEXT of the calling statement, so
        # tracing the parameters by shape alone would leave the guarantee resting on every call site
        # happening to pass a variable rather than a literal - true of all five today, and not
        # something the code enforces. Caller and line number still identify the push exactly.
        #
        # Same treatment, for the same reason, as Invoke-ExecuteScriptAsync one frame down.
        $Private:TracedParameter = [Ordered]@{
            ScriptToExecute = "<{0} characters>" -f ([string]$ScriptToExecute).Length
        }
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Parameters: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), (ConvertTo-RedactedLogString -InputObject $Private:TracedParameter -MaxDepth 1)))
        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    "Editor value updated!" | Write-LogOutput -LogType DEBUG
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }
            }
            catch {
                $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }

        Invoke-ExecuteScriptAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
