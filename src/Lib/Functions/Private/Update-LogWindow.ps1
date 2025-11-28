function Update-LogWindow {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if ($null -ne $Script:TextBoxLog) {
            $Script:TextBoxLog.Dispatcher.Invoke({
                    $Script:TextBoxLog.AppendText($LogMessage.Text + "`n")
                    if ($Script:TextBoxLog.IsLoaded -and (Invoke-LogWindowScrollToEnd)) {
                        $Script:TextBoxLog.ScrollToEnd()
                    }
                })
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
