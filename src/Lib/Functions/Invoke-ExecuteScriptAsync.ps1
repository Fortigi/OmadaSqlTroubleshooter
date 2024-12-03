function Invoke-ExecuteScriptAsync {

    PARAM(
        $ScriptToExecute,
        $OnCompletedScriptBlock
    )
    try {
        if ($null -ne $Script:WebView.CoreWebView2) {
            $Script:Task = $Script:WebView.CoreWebView2.ExecuteScriptAsync($ScriptToExecute)
            $Script:Task.GetAwaiter().OnCompleted($OnCompletedScriptBlock)
        }
        else {
            Write-LogOutput -Message "WebView2 is not initialized." -LogType ERROR
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
