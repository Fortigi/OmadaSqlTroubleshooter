function Test-TabCapacity {
    <#
    .SYNOPSIS
    Determines whether another tab may be opened without exceeding the configured tab capacity.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$CurrentCount,
        [int]$MaxCapacity = 8
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        return $CurrentCount -lt $MaxCapacity
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
