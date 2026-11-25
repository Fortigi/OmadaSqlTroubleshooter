# What Wait-E2ENoPendingRequests does when the queue does NOT drain.
#
# Kept apart from Drivers.ps1 because nothing here touches the application: it reads and edits a
# queue it is handed, so the unit lane can test it (tests\E2EPendingRequestDrain.Tests.ps1) without
# a window, a dispatcher or the module.
#
# Why it exists. Scheduled run 155 failed three consecutive Validation cases with nothing but
# "Timed out after 15s waiting for: pending background requests to drain". The same commit passed
# four other scheduled runs, so it was a hung or very slow request - but the message did not say
# WHICH request, and because the stuck item was left on the queue every following case that drained
# failed on the same item. One hang reported as three failures, none of them diagnosable.
#
# So on a timeout the harness now:
#   1. names every request still in flight (description, tab, age, whether its worker finished), and
#   2. evicts them - pipeline stopped, shell disposed, item off the queue, marked cancelled - so the
#      hang costs the one case that met it, and the next case starts from an empty queue.
#
# The case that timed out still FAILS. Eviction stops the cascade; it does not hide the hang.

function script:Get-E2EInFlightRequest {
    # The items the drain waits on: background requests, which carry StartedUtc. Editor tasks and
    # validation workers carry none and are not part of the drain condition, so they are left alone.
    param(
        [AllowNull()]
        $Pending
    )
    if ($null -eq $Pending) {
        return @()
    }
    return @($Pending | Where-Object { $null -ne $_ -and $null -ne $_.StartedUtc })
}

function script:Format-E2EInFlightRequest {
    # One line per request, e.g.
    #   'Executing query' on tab 3f2a... for 15.2s (worker finished: False)
    # "worker finished: True" on a stuck item means the poll timer never collected it - a different
    # defect from a worker that is still running, and the reason the flag is in the message.
    param(
        [AllowNull()]
        $Request,

        [DateTime]$NowUtc = [DateTime]::UtcNow
    )
    $Private:Line = foreach ($Private:Item in @(Get-E2EInFlightRequest -Pending $Request)) {
        $Private:TabId = if ($null -ne $Private:Item.TabSession) { [string]$Private:Item.TabSession.Id } else { "<none>" }
        $Private:Description = if ([string]::IsNullOrWhiteSpace([string]$Private:Item.Description)) { "<no description>" } else { [string]$Private:Item.Description }
        $Private:Finished = $null -ne $Private:Item.Task -and [bool]$Private:Item.Task.IsCompleted
        "'{0}' on tab {1} for {2:N1}s (worker finished: {3})" -f $Private:Description, $Private:TabId, ($NowUtc - [DateTime]$Private:Item.StartedUtc).TotalSeconds, $Private:Finished
    }
    return (@($Private:Line) -join "; ")
}

function script:Clear-E2EInFlightRequest {
    # Evict every in-flight background request from the queue. Returns what was evicted.
    param(
        [AllowNull()]
        $Pending
    )
    $Private:Evicted = @(Get-E2EInFlightRequest -Pending $Pending)
    foreach ($Private:Item in $Private:Evicted) {
        [void]$Pending.Remove($Private:Item)
        $Private:Item.IsCancelled = $true
        if ($null -ne $Private:Item.Shell) {
            try {
                [void]$Private:Item.Shell.BeginStop($null, $null)
                $Private:Item.Shell.Dispose()
            }
            catch {
                # A worker that already finished, or a shell already disposed: the item is off the
                # queue, which is the part that matters for the next case.
            }
        }
    }
    return $Private:Evicted
}
