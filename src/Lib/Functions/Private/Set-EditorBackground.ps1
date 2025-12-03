function Set-EditorBackground {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $OnCompletedScriptBlock = {
            try {
                if (!$Script:Task.Status -eq "RanToCompletion") {
                    "Monaco Editor Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Monaco Editor Task completed successfully." | Write-LogOutput -LogType DEBUG
                }
            }
            catch {
                $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }
        $ScriptToExecute = "container.style.backgroundImage = url('`${0}');" -f (Get-Icon -Type Base64)
        Invoke-ExecuteScriptAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
        $ScriptToExecute = "container.style.backgroundSize = `"200px 200px`";"
        Invoke-ExecuteScriptAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
        $ScriptToExecute = "container.style.backgroundPosition = `"center`";"
        Invoke-ExecuteScriptAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
        $ScriptToExecute = "container.style.backgroundRepeat = `"no-repeat`";"
        Invoke-ExecuteScriptAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
