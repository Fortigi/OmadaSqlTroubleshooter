function Invoke-ExecuteScriptAsync {
    PARAM(
        $ScriptToExecute,
        $OnCompletedScriptBlock
    )
    try {

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
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
