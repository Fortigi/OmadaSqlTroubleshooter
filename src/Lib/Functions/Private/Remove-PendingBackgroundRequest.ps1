function Remove-PendingBackgroundRequest {
    <#
    .SYNOPSIS
    Abandon and discard every background request belonging to a tab that is going away.

    .DESCRIPTION
    Found while building issue #40's E2E coverage, and it is a real defect rather than a tidiness
    measure. Nothing has ever removed a closing tab's entries from
    $Script:PendingWebViewCompletions. That was survivable while the queue only held WebView2 editor
    tasks - a completion for a disposed control does very little - but a background request's
    completion does a great deal: the poll timer calls Set-ActiveTabContext with the item's
    TabSession, which repoints $Script:MainForm.Elements, $Script:RunTimeData, $Script:AppConfig and
    $Script:ConnectionStatus onto a tab that no longer exists, and then invokes a completion block
    that writes results into disposed WPF elements. The restore in the timer's finally cannot save
    it either: Get-ActiveTabSession returns $null when the closing tab was the active one, and the
    restore is skipped.

    So a query left running on a tab the user then closes would quietly redirect the whole
    application's UI state onto the dead tab.

    The pipeline is stopped rather than merely dropped, so the worker is not left holding a runspace
    for a result nobody will read; the shell is disposed for the same reason
    Complete-OmadaBackgroundRequest disposes it - a pipeline killed mid-request leaves a half-read
    HTTP stream and a WebRequestSession in an unknown state, and its runspace must not be handed back
    to the pool.

    Editor tasks (items with no StartedUtc) are left alone: they are not ours to stop, they carry no
    worker, and the existing behaviour around them is unchanged.

    .PARAMETER TabSession
    The tab being closed.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )

    try {
        if ($null -eq $Script:PendingWebViewCompletions) {
            return
        }

        $Private:Orphaned = @($Script:PendingWebViewCompletions | Where-Object {
                $null -ne $_.StartedUtc -and $null -ne $_.TabSession -and $_.TabSession.Id -eq $TabSession.Id
            })

        foreach ($Private:Item in $Private:Orphaned) {
            [void]$Script:PendingWebViewCompletions.Remove($Private:Item)
            $Private:Item.IsCancelled = $true

            try {
                if ($null -ne $Private:Item.Shell) {
                    [void]$Private:Item.Shell.BeginStop($null, $null)
                    $Private:Item.Shell.Dispose()
                }
            }
            catch {
                # A worker that had already finished throws here. Nothing to recover: the item is
                # off the queue, which is the part that matters.
            }
        }

        if ($Private:Orphaned.Count -gt 0) {
            "Abandoned {0} background request(s) belonging to closed tab '{1}'." -f $Private:Orphaned.Count, $TabSession.DisplayName | Write-LogOutput -LogType DEBUG
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
