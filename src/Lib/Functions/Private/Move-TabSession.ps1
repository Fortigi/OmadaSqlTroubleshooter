function Move-TabSession {
    <#
    .SYNOPSIS
    Reorders tabs by moving the dragged tab to the target tab's position, keeping $Script:Tabs and
    the TabControl's item order in sync (drag-to-reorder). No-ops if either tab is missing or they
    are the same tab. The dragged tab stays selected afterwards.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DraggedTabId,
        [Parameter(Mandatory = $true)]
        [string]$TargetTabId
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ($DraggedTabId -eq $TargetTabId) {
            return
        }

        $DraggedTab = $Script:Tabs | Where-Object { $_.Id -eq $DraggedTabId } | Select-Object -First 1
        $TargetTab = $Script:Tabs | Where-Object { $_.Id -eq $TargetTabId } | Select-Object -First 1
        if ($null -eq $DraggedTab -or $null -eq $TargetTab) {
            return
        }

        $TabControlSessions = Get-TabControlSessions

        # Reorder in the TabControl. Direction matters: dropping a tab onto one to its right lands
        # it AFTER the target, onto one to its left lands it BEFORE - otherwise dragging rightward
        # would be a no-op. Indices are captured before removing the dragged item, then the target's
        # post-removal index is used so the "+" add tab and the other tabs keep their order.
        $DraggedIndexBefore = $TabControlSessions.Items.IndexOf($DraggedTab.TabItem)
        $TargetIndexBefore = $TabControlSessions.Items.IndexOf($TargetTab.TabItem)
        [void]$TabControlSessions.Items.Remove($DraggedTab.TabItem)
        $TargetIndexAfter = $TabControlSessions.Items.IndexOf($TargetTab.TabItem)
        if ($TargetIndexAfter -lt 0) {
            $TargetIndexAfter = 0
        }
        $InsertIndex = if ($DraggedIndexBefore -lt $TargetIndexBefore) { $TargetIndexAfter + 1 } else { $TargetIndexAfter }
        if ($InsertIndex -gt $TabControlSessions.Items.Count) {
            $InsertIndex = $TabControlSessions.Items.Count
        }
        $TabControlSessions.Items.Insert($InsertIndex, $DraggedTab.TabItem)

        # Mirror the same order in $Script:Tabs so persistence/iteration match the visible order.
        $DraggedTabsIndexBefore = $Script:Tabs.IndexOf($DraggedTab)
        $TargetTabsIndexBefore = $Script:Tabs.IndexOf($TargetTab)
        [void]$Script:Tabs.Remove($DraggedTab)
        $TargetTabsIndexAfter = $Script:Tabs.IndexOf($TargetTab)
        if ($TargetTabsIndexAfter -lt 0) {
            $Script:Tabs.Add($DraggedTab)
        }
        else {
            $TabsInsertIndex = if ($DraggedTabsIndexBefore -lt $TargetTabsIndexBefore) { $TargetTabsIndexAfter + 1 } else { $TargetTabsIndexAfter }
            if ($TabsInsertIndex -gt $Script:Tabs.Count) {
                $TabsInsertIndex = $Script:Tabs.Count
            }
            $Script:Tabs.Insert($TabsInsertIndex, $DraggedTab)
        }

        $TabControlSessions.SelectedItem = $DraggedTab.TabItem
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
