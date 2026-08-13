function Invoke-SaveEditorValue {
    [CmdLetBinding()]
    param(
        [switch]$NewQuery
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $ScriptToExecute = "editor.getValue();"
        $Script:NewQuery = $NewQuery
        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -eq "RanToCompletion") {
                    $Script:RunTimeData.QueryText = $Script:Task.Result

                    if (![string]::IsNullOrWhiteSpace($Script:RunTimeData.QueryText.ResultAsJson)) {
                        $Script:RunTimeData.QueryText = $Script:RunTimeData.QueryText.ResultAsJson | ConvertFrom-Json
                    }
                    else {
                        $Script:RunTimeData.QueryText = $Script:RunTimeData.QueryText | ConvertFrom-Json
                    }
                    $SaveResult = Save-Query -NewQuery:$Script:NewQuery
                    if ($null -ne $SaveResult) {
                        $TabSession = Get-ActiveTabSession
                        if ($null -ne $TabSession) {
                            $TabSession.IsDirty = $false
                            Update-TabHeaderTitle -TabSession $TabSession
                        }
                    }
                }
                elseif ($Script:Task.Status -eq "Faulted") {
                    "Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else {
                    "Task result: {0}" -f $Script:Task.Status | Write-LogOutput -LogType DEBUG
                }

                $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
                $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
            }
            catch {
                $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }
        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
