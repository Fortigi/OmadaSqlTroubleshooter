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

    # Wrapped as a whole, and per item, because this runs from the completion poll timer's Tick: an
    # exception escaping here would abort that Tick before it drained any completions, so one
    # malformed queue item could stall every pending result behind a cosmetic status-bar update.
    # A missing tab or element bag is a skip, never a failure.
    try {
        foreach ($Item in @($Pending)) {
            try {
                if ($null -eq $Item -or $null -eq $Item.StartedUtc -or $Item.IsCancelled) {
                    continue
                }
                if ($null -eq $Item.TabSession -or $null -eq $Item.TabSession.Elements) {
                    continue
                }

                $Private:TimeBlock = $Item.TabSession.Elements.TextBlockStatusBarQueryTime
                if ($null -eq $Private:TimeBlock) {
                    continue
                }

                # Formatted like the final value Reset-ExecuteQueryUiState writes from the stopwatch,
                # so the indicator does not visibly change shape when the request completes.
                $Private:TimeBlock.Text = Format-ElapsedTime -TimeSpan ([DateTime]::UtcNow - $Item.StartedUtc)
            }
            catch {
                continue
            }
        }
    }
    catch {
        # Deliberately silent: this is a cosmetic indicator, and it runs twenty times a second.
        # Logging a failure here would flood the log for something the user cannot act on.
    }
}
