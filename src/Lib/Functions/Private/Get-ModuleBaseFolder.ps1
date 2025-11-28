function Get-ModuleBaseFolder {
    [CmdletBinding()]
    PARAM()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        "Return Module Base Folder" | Write-LogOutput -LogType VERBOSE
        return Split-Path -Path ($MyInvocation.MyCommand.Module).Path -Parent
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
