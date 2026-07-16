function Get-InstalledModuleInfo {
    [CmdletBinding()]
    param(
        [string]$ModuleName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $CallStack = Get-PSCallStack
        $ModuleStack = $CallStack | Where-Object { $_.Command -eq ("{0}.psm1" -f $ModuleName) }

        $Module = Get-Module -ListAvailable -Name $ModuleName | ForEach-Object { $_ | Where-Object { (Split-Path $_.Path) -eq (Split-Path $ModuleStack.ScriptName) } } | Sort-Object Version -Descending | Select-Object -First 1
        if ($Module) {
            $ModuleInfo = [pscustomobject]@{
                Name             = $Module.Name
                Version          = $Module.Version
                FullVersion      = "{0}-{1}" -f $Module.Version, $Module.PrivateData?.PSData?.Prerelease
                RepositorySource = $Module.RepositorySourceLocation
                PreRelease       = $Module.PrivateData?.PSData?.Prerelease
                IsPreRelease     = -not [string]::IsNullOrWhiteSpace($Module.PrivateData?.PSData?.Prerelease)
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
