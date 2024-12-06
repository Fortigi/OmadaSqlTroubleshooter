function Push-ToEditor {
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$ScriptToExecute
    )
    try {
        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    "Editor value updated!" | Write-LogOutput -LogType DEBUG
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }
            }
            catch {
                $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR
            }
        }

        Invoke-ExecuteScriptAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
