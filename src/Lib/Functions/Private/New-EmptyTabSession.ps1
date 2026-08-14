function New-EmptyTabSession {
    <#
    .SYNOPSIS
    Opens a new empty tab if the configured tab capacity allows it, otherwise warns. Shared by the
    "+" add-tab click and the tab context menu's "New Tab" item (Ctrl+T is bound to duplicating the
    active tab without its query instead - see Invoke-DuplicateTab).
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $MaxCapacity = if ($null -ne $Script:AppGlobalConfig -and $Script:AppGlobalConfig.TabCapacity -gt 0) { $Script:AppGlobalConfig.TabCapacity } else { 8 }
        if (Test-TabCapacity -CurrentCount $Script:Tabs.Count -MaxCapacity $MaxCapacity) {
            return New-TabSession
        }

        "Cannot open a new tab: capacity of {0} tabs reached." -f $MaxCapacity | Write-LogOutput -LogType WARNING
        return $null
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        return $null
    }
}
