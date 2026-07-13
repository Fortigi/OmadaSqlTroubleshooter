function Get-ActiveTabSession {
    <#
    .SYNOPSIS
    Returns the tab session object that is currently active (in context).
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        # -First 1 guarantees a single object (or $null) rather than a collection, so every
        # caller's "$null -ne $TabSession" check followed by property access stays reliable.
        return $Script:Tabs | Where-Object { $_.Id -eq $Script:ActiveTabId } | Select-Object -First 1
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
