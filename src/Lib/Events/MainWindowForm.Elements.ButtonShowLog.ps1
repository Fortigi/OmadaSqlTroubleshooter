$Script:MainWindowForm.Elements.ButtonShowLog.Add_Click({
    $_ | Show-EventInfo
    if (Test-LogWindowOpen) {
        "Hide log" | Write-LogOutput -LogType DEBUG
        $Script:LogWindowForm.Definition.Close()
    }
    else {
        "Show log" | Write-LogOutput -LogType DEBUG
        Open-LogWindow
    }

})
