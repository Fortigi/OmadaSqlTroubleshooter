function Invoke-ExecuteScriptAsync {
    [CmdLetBinding()]
    param(
        $ScriptToExecute,
        $OnCompletedScriptBlock
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -ne $Script:Webview.Object) {
            if ($Script:Webview.Object.IsLoaded) {
                $Script:Task = $Script:Webview.Object.CoreWebView2.ExecuteScriptAsync($ScriptToExecute)
                $Script:Task.GetAwaiter().OnCompleted($OnCompletedScriptBlock)
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
