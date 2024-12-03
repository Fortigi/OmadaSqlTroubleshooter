$Script:MainWindowForm.Definition.Add_Closed({
    $_ | Show-EventInfo
    $Script:MainWindowForm.Definition.Close()
    if (Test-LogWindowOpen) {
        $Script:LogWindowForm.Definition.Close()
    }
})
