function Close-OtherTabSessions {
    <#
    .SYNOPSIS
    Closes every tab except the one identified by -KeepTabId ("Close all but this"). Tabs with
    unsaved changes still get their save prompt via Close-TabSession.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeepTabId
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $TabIds = @($Script:Tabs | Where-Object { $_.Id -ne $KeepTabId } | ForEach-Object { $_.Id })
        foreach ($TabId in $TabIds) {
            Close-TabSession -TabId $TabId
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
