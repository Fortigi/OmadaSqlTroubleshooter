function Get-InstalledModuleInfo {
    [CmdLetBinding()]
    param (
        [string]$ModuleName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $Module = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
        if ($Module) {
            $ModuleInfo = @{
                Name             = $Module.Name
                Version          = $Module.Version
                RepositorySource = $Module.RepositorySourceLocation
            }
            return $ModuleInfo
        }
        else {
            return $null
        }
    }
    catch {
        return $null
    }
}
