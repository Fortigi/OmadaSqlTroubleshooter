function Invoke-SaveEditorValue {
    [CmdLetBinding()]
    PARAM(
        [switch]$NewQuery
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $ScriptToExecute = "editor.getValue();"
        $Script:NewQuery = $NewQuery
        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $Script:RunTimeData.QueryText = $Script:Task.Result
                    if (![string]::IsNullOrWhiteSpace($Script:RunTimeData.QueryText.ResultAsJson)) {
                        $Script:RunTimeData.QueryText = $Script:RunTimeData.QueryText.ResultAsJson | ConvertFrom-Json
                    }
                    Save-Query -NewQuery:$Script:NewQuery | Out-Null
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }
                $Script:MainWindowForm.Elements.ButtonSaveQuery.IsEnabled = $True
                $Script:MainWindowForm.Elements.ButtonExecuteQuery.IsEnabled = $True
            }
            catch {
                $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
