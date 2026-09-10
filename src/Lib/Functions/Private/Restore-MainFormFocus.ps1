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
        # DEBUG, and this one must never be an ERROR.
        #
        # Show-LogMessageDialog calls this immediately after a dialog closes - so this runs INSIDE the
        # logging path. Write-LogOutput ends an ERROR with Write-Error, terminating under the
        # application's $ErrorActionPreference = Stop, which means reporting a failure here would
        # throw out of the code that was itself reporting a failure. That is the shape of the cascade
        # that turned one HTTP 500 into five stacked dialogs.
        #
        # Re-activating the main window is cosmetic; there is nothing the user can do about it and
        # nothing worth interrupting them for.
        "Could not return focus to the main window: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
