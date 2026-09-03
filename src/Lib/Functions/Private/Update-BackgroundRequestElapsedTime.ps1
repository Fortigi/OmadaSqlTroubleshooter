function Update-BackgroundRequestElapsedTime {
    <#
    .SYNOPSIS
    Write a live elapsed time into the status bar of every tab that has a background request in
    flight.

    .DESCRIPTION
    Issue #40's elapsed-time indicator. Before this, $Script:RunTimeData.StopWatch was read exactly
    once - at the very end of an execute - so the number only appeared after the wait was over, which
    is the one moment it is of no use.

    Deliberately NOT a second DispatcherTimer. It is driven from the existing 50 ms completion poll
    timer, which is already the single place that knows about pending work, and is already correctly
    suspended around modal dialogs. A second timer would have to learn both of those things again,
    and would tick while a modal was open - the exact reentrancy problem
    Suspend-WebViewCompletionPolling exists to prevent.

    Writes to the OWNING tab's element rather than $Script:MainForm.Elements, and so needs no
    Set-ActiveTabContext: repointing the whole application state twenty times a second, purely to
    write a string, would be an absurd cost and a real risk. A tab executing in the background
    therefore counts up while the user watches a different tab, which is the correct behaviour
    anyway.

    .PARAMETER Pending
    The queue items to consider. Items without a StartedUtc (WebView2 editor tasks) are ignored.
    #>
    [CmdLetBinding()]
    param(
        $Pending
    )

    foreach ($Item in @($Pending)) {
        if ($null -eq $Item -or $null -eq $Item.StartedUtc -or $Item.IsCancelled) {
            continue
        }

        $Private:TimeBlock = $Item.TabSession.Elements.TextBlockStatusBarQueryTime
        if ($null -eq $Private:TimeBlock) {
            continue
        }

        # Formatted like the final value Reset-ExecuteQueryUiState writes from the stopwatch, so the
        # indicator does not visibly change shape at the moment the request completes.
        $Private:TimeBlock.Text = ([DateTime]::UtcNow - $Item.StartedUtc).ToString()
    }
}
