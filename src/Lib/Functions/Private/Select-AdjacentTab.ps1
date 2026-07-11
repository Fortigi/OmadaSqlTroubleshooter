function Select-AdjacentTab {
    <#
    .SYNOPSIS
    Selects the tab next to the active one, wrapping around: -Direction Next moves right (and from
    the last tab jumps to the first), -Direction Previous moves left (and from the first tab jumps
    to the last). Only the real session tabs are cycled - the "+" add tab is never selected. Drives
    the Ctrl+Tab / Ctrl+Shift+Tab shortcuts.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Next", "Previous")]
        [string]$Direction
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Count = $Script:Tabs.Count
        if ($Count -le 1) {
            return
        }

        # $Script:Tabs is kept in the same order as the visible tabs (Move-TabSession keeps drag
        # reordering in sync), so its index order is the left-to-right tab order.
        $Active = Get-ActiveTabSession
        $Index = if ($null -ne $Active) { $Script:Tabs.IndexOf($Active) } else { 0 }
        if ($Index -lt 0) {
            $Index = 0
        }

        $NewIndex = if ($Direction -eq "Next") { ($Index + 1) % $Count } else { ($Index - 1 + $Count) % $Count }
        (Get-TabControlSessions).SelectedItem = $Script:Tabs[$NewIndex].TabItem
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
