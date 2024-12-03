function Set-MonacoSchema {
    PARAM(
        $ReturnValue
    )
    try {
        "Add schema to Monaco editor." | Write-LogOutput -LogType DEBUG
        $TableObjects = @()
        foreach ($Table in ($ReturnValue.d | Get-Member -MemberType NoteProperty)) {
            $TableName = $($Table.Name).Split(".")[1]
            $TableObject = [pscustomobject]@{
                $TableName = @()
            }
            foreach ($Column in $ReturnValue.d.$($Table.Name)) {
                $TableObject.$TableName += $Column.Split(" ")[0]
            }
            $TableObjects += $TableObject
        }
        $TableObjectsJson = $TableObjects | ConvertTo-Json -Depth 5

        "Schema for Monaco editor." | Write-LogOutput -LogType VERBOSE
        $OnCompletedScriptBlock = {
            try {
                if (!$Script:Task.Status -eq "RanToCompletion") {
                    "Monaco Editor Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                }
                else{
                    "Monaco Editor Task completed successfully." | Write-LogOutput -LogType DEBUG
                }
            }
            catch {
                $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR
            }
        }

        "Push schema to Monaco editor." | Write-LogOutput -LogType DEBUG
        Invoke-ExecuteScriptAsync -ScriptToExecute "setSchema($TableObjectsJson);" -OnCompletedScriptBlock $OnCompletedScriptBlock

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
