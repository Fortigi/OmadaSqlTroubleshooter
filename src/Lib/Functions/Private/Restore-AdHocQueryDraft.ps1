function Restore-AdHocQueryDraft {
    <#
    .SYNOPSIS
        At start-up, offers to restore the ad-hoc queries that were not saved when the application last
        closed or crashed.

    .DESCRIPTION
        Runs once, after Restore-TabSessions has opened the tabs. Restoring is at the user's request:
        nothing is put back without asking, because a draft can be days old and about a tenant the
        user no longer works on.

          Restore  Each draft goes back into its own tab when that tab was restored (a normal close),
                   or into a new tab opened from the connection settings the draft carries (a crash,
                   where tabs.clixml was never rewritten). New tabs are deferred - created cheaply and
                   connected only when first selected - and the tab that was active stays active.
          Discard  Every draft is deleted.
          Neither  Closing the dialog keeps the drafts for the next start.

        A reset discards the drafts without asking, together with the tab sessions.

        A draft that cannot get a tab because the tab capacity is reached is kept, with a warning,
        rather than dropped.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3})" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber)))

        if ($Script:RunTimeConfig.ResetRequested) {
            Remove-AdHocQueryDraft -All
            return
        }

        $Private:Drafts = @(Get-AdHocQueryDraft)
        if ($Private:Drafts.Count -eq 0) {
            return
        }

        $Private:Choice = Open-ChoiceForm -Title "Restore ad-hoc queries?" -Message ("{0} ad-hoc query(ies) from the previous session were not saved to Omada. Restore them?" -f $Private:Drafts.Count) -LeftButtonText "Restore" -RightButtonText "Discard"
        if ($Private:Choice -eq $false) {
            "Discarding {0} ad-hoc query draft(s) at the user's request." -f $Private:Drafts.Count | Write-LogOutput -LogType DEBUG
            Remove-AdHocQueryDraft -All
            return
        }
        if ($Private:Choice -ne $true) {
            return
        }

        $Private:Plan = Resolve-AdHocQueryDraftRestore -Draft $Private:Drafts -TabId @($Script:Tabs | ForEach-Object { $_.Id })

        foreach ($Private:Entry in $Private:Plan.Attach) {
            $Private:Tab = $Script:Tabs | Where-Object { $_.Id -eq $Private:Entry.TabId } | Select-Object -First 1
            Set-AdHocQueryDraftOnTab -TabSession $Private:Tab -Draft $Private:Entry.Draft
        }

        if ($Private:Plan.Open.Count -gt 0) {
            Open-AdHocQueryDraftTab -Draft $Private:Plan.Open
        }

        "Restored {0} ad-hoc query draft(s)." -f $Private:Drafts.Count | Write-LogOutput -LogType DEBUG
    }
    catch {
        "Restoring the ad-hoc query drafts failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
    }
}

function Open-AdHocQueryDraftTab {
    <#
    .SYNOPSIS
        Opens a new, deferred tab for each ad-hoc query draft whose own tab no longer exists, and
        leaves the tab that was active selected.

    .PARAMETER Draft
        The drafts to open tabs for.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Draft
    )

    $Private:Previous = Get-ActiveTabSession

    foreach ($Private:Item in $Draft) {
        $Private:Config = $Private:Item.TabConfig
        if ($null -eq $Private:Config) {
            $Private:Config = ConvertTo-AdHocQueryDraftTabConfig -TabId $Private:Item.TabId -AppConfig $null
        }

        $Private:Tab = New-TabSession -RestoreFrom $Private:Config -Deferred
        if ($null -eq $Private:Tab) {
            "No tab could be opened for an ad-hoc query draft; it is kept for the next start." | Write-LogOutput -LogType WARNING -SkipDialog
            continue
        }
        Set-AdHocQueryDraftOnTab -TabSession $Private:Tab -Draft $Private:Item
    }

    if ($null -eq $Private:Previous) {
        return
    }

    $Script:SuppressEditorSync = $true
    try {
        (Get-TabControlSessions).SelectedItem = $Private:Previous.TabItem
    }
    finally {
        $Script:SuppressEditorSync = $false
    }
    Set-ActiveTabContext -TabSession $Private:Previous
}
