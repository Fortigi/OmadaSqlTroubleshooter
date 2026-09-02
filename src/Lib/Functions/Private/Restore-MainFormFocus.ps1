function Restore-MainFormFocus {
    [CmdLetBinding()]
    param()
    try {
        if ($null -ne $Script:MainForm -and $null -ne $Script:MainForm.Definition) {
            $Script:MainForm.Definition.Dispatcher.Invoke({
                    $Script:MainForm.Definition.Activate()
                })
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
