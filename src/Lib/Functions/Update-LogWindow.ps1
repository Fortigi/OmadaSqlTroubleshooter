function Update-LogWindow {

    try {
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
