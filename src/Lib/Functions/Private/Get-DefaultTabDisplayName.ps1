function Get-DefaultTabDisplayName {
    <#
    .SYNOPSIS
    Builds the default display name for a tab whose Display name field was left blank.
    #>
    [CmdLetBinding()]
    param(
        [datetime]$Date = (Get-Date)
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        return "SqlQuery_{0}" -f $Date.ToString("yyyyMMddHHmmss")
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
