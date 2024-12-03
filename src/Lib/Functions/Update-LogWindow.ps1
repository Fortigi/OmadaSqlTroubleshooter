function Update-LogWindow {

    try {
        if ($null -ne $Script:TextBoxLog) {
            $Script:TextBoxLog.Dispatcher.Invoke({
                    $Script:TextBoxLog.AppendText($LogMessage.Text + "`r`n")
                    if (Invoke-LogWindowScrollToEnd) {
                        $Script:TextBoxLog.ScrollToEnd()
                    }
                })
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
