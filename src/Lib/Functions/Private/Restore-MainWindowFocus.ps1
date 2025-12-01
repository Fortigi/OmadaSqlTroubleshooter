function Restore-MainWindowFocus {
    [CmdLetBinding()]
    param()
    try {
        if ($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definition) {
            $Script:MainWindowForm.Definition.Dispatcher.Invoke({
                    $Script:MainWindowForm.Definition.Activate()
                })
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
