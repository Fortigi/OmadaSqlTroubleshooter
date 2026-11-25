function Invoke-AdHocQueryDraftTimerTick {
    <#
    .SYNOPSIS
        Writes the ad-hoc query drafts of tabs that changed since the last write, from the completion
        poll timer.

    .DESCRIPTION
        Typing queues the write (Set-TabEditorText sets DraftPending); this performs it, at most once
        every -Interval ticks. With the timer's 50 ms interval and the default of 40 that is every two
        seconds: rare enough that typing never waits on the disk, often enough that a crash loses at
        most the last two seconds of an ad-hoc query.

        Driven from the existing WebViewCompletionPollTimer rather than a timer of its own, like the
        elapsed-time indicator and the session keep-alive: that timer is already suspended around
        modal dialogs, so no write runs while a dialog is deciding what happens to a tab.

    .PARAMETER TickCount
        The poll timer's tick counter.

    .PARAMETER Interval
        Write every this many ticks.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [long]$TickCount,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Interval = 40
    )

    if ($TickCount % $Interval -ne 0) {
        return
    }

    foreach ($Private:Tab in @($Script:Tabs | Where-Object { $null -ne $_ -and $true -eq $_.DraftPending })) {
        Sync-AdHocQueryDraft -TabSession $Private:Tab
    }
}
