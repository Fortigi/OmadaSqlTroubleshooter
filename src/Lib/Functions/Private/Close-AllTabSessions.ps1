function Close-AllTabSessions {
    <#
    .SYNOPSIS
    Closes every open tab. Closing the final tab leaves only the "+" add tab, with no tab active -
    it is not auto-reopened. Each tab is routed through Close-TabSession, so tabs with unsaved
    changes still get their save prompt.
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
