function Restore-MainFormFocus {
    [CmdLetBinding()]
    param()
    try {
        if ($null -ne $Script:MainFormForm -and $null -ne $Script:MainFormForm.Definition) {
            $Script:MainFormForm.Definition.Dispatcher.Invoke({
                    $Script:MainFormForm.Definition.Activate()
                })
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
