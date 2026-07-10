function Close-AllTabSessions {
    <#
    .SYNOPSIS
    Closes every open tab. Because the app never allows zero tabs, closing the final tab opens a
    fresh empty one - so "Close All" effectively resets down to a single blank tab. Each tab is
    routed through Close-TabSession, so tabs with unsaved changes still get their save prompt.
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        # Snapshot the ids first: Close-TabSession mutates $Script:Tabs as it goes.
        $TabIds = @($Script:Tabs | ForEach-Object { $_.Id })
        foreach ($TabId in $TabIds) {
            Close-TabSession -TabId $TabId
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
