# The label a view lookup carries on the completion queue. A constant because it is matched, not
# just displayed - see Start-SqlTroubleShooterViewLookup, which reads the queue through it.
$Script:SqlTroubleShooterViewRequestDescription = "SQL Troubleshooting view"

function Get-SqlTroubleShooterView {
    <#
    .SYNOPSIS
    Find the "SQL Troubleshooting" view and return its data object rows, on the UI thread.

    .DESCRIPTION
    The blocking form, unchanged in behaviour: two dependent GetPagingData round-trips. It remains
    the fallback for every case where a background worker may not be used, and it is what
    Start-SqlTroubleShooterViewLookup retries on when a worker could not do the job.

    Both round-trips are built by New-OmadaPagingRequest, the same builder the background pipeline
    uses, so the inline and background paths cannot drift apart.
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $ViewResult = Get-OmadaGetPagingDataObject -SearchString "SQL Troubleshooting" -DataType "Views" -DataTypeArgs @{OwnerShipType = "Both" }
        $View = $null
        if ($null -ne $ViewResult -and $ViewResult.d.Records -gt 0) {
            # -First 1, matching Invoke-OmadaViewLookupPipeline. A tenant holding two views of this
            # name would otherwise make $View an array here, and "{0}" -f an array formats as
            # System.Object[] - an invalid viewId and pageQueryString. The two paths must not differ
            # on this: one definition of the request is the whole point of New-OmadaPagingRequest.
            $View = $ViewResult.d.Rows | Where-Object { $_.Name -eq "SQL Troubleshooting" } | Select-Object -First 1
        }
        $Private:Result = $null
        if ($null -ne $View) {
            $DataTypeArgs = [ordered]@{
                viewId          = ("{0}" -f $View.Id)
                pageQueryString = ("{0}/dataobjlst.aspx?view={1}" -f $Script:AppConfig.BaseUrl, $View.Id)
                readOnlyMode    = $false
                countRows       = $false
            }

            $Private:Result = Get-OmadaGetPagingDataObject -DataType "DataObjects" -DataTypeArgs $DataTypeArgs
            # Normalised to an array, matching Invoke-OmadaViewLookupPipeline. A jqGrid payload for a
            # view holding nothing has a NULL .d.Rows, and @($null).Count is 1 - so every caller
            # asking "did I get rows?" the obvious way was told yes for no rows at all. Answering it
            # here means no caller has to know that.
            $Private:Result = @($Private:Result.d.Rows | Where-Object { $null -ne $_ })
        }
        return $Private:Result

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}

function Start-SqlTroubleShooterViewLookup {
    <#
    .SYNOPSIS
    Run the view lookup on a background worker and hand its rows to a completion block on the UI
    thread. Returns $null - having done nothing - when it must run inline instead.

    .DESCRIPTION
    Issue #90, slice A. The two round-trips go to the worker as ONE job (see
    Invoke-OmadaViewLookupPipeline for why one and not two), so this costs one completion, which is
    the number of places Set-ActiveTabContext can repoint underneath the work.

    The contract is Invoke-OmadaPSWebRequestWrapperAsync's, deliberately: $null means "not
    dispatched, do what you did before", so a caller keeps its synchronous path verbatim rather than
    growing a second implementation of it.

    .PARAMETER OnResultScriptBlock
    A PLAIN scriptblock (never .GetNewClosure()) invoked on the UI thread with two arguments: a
    result hashtable, and the caller's own $Context echoed back. The result carries:

      Rows            the view's data object rows, or $null
      DataObjectHtml  the dataobjdlg.aspx response, when -IncludeDataObjectHtml was asked for
      RetryInline     $true when the worker could not do the job at all. The caller then runs its
                      OWN synchronous path - the same one it runs when this function returns $null -
                      rather than this function keeping a second copy of it.

    .PARAMETER Context
    Caller data carried to the completion. Read there rather than re-read from $Script: state, which
    by then may belong to a different tab.

    .PARAMETER IncludeDataObjectHtml
    Also fetch the dataobjdlg.aspx page for the first row, as a third step of the same worker job.
    Update-DataConnectionList needs it; Update-QueryList does not.

    .OUTPUTS
    The pending queue item, or $null when the caller must run the lookup synchronously.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$OnResultScriptBlock,

        $Context,

        [switch]$IncludeDataObjectHtml
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        # Already in flight for this tab? Both of this lookup's callers can be triggered together -
        # Update-DataConnectionList and Update-QueryList are called one after the other on connect -
        # and the answer is the same for both. Read straight off the completion queue rather than
        # from a side table of "lookups in flight": a side table has to be cleared on success,
        # failure AND abandonment when the tab closes, and an entry left behind on that last path
        # would block the tab from ever looking the view up again. The queue cannot get out of step
        # with itself. (The same reasoning, and the same shape, as Get-SqlSchemaObject's guard.)
        #
        # It returns the OUTSTANDING item, never $null. $null is this function's "not dispatched, do
        # what you did before" answer, and the caller's "before" is the three blocking round-trips
        # this whole slice exists to remove - so answering $null here would defeat the guard AND put
        # the freeze back, which is worse than the duplicate request it was meant to prevent.
        #
        # Matched on shape as well as tab: a lookup running WITHOUT the data connection page cannot
        # satisfy a caller that needs it, and joining it would leave that caller waiting for data the
        # worker was never asked to fetch.
        #
        # The joining caller's own result block does not run - the outstanding request's does, and
        # for the same shape on the same tab it does the same work. What it does not carry is the
        # second caller's context, so where those differ the first call's wins. Today that is only
        # -NotShowPopupWindow, i.e. whether a popup appears during a refresh that is already
        # happening.
        $Private:TabSession = Get-ActiveTabSession
        if ($null -ne $Private:TabSession) {
            $Private:Outstanding = @($Script:PendingWebViewCompletions | Where-Object {
                    $_.Description -eq $Script:SqlTroubleShooterViewRequestDescription -and
                    $_.TabSession.Id -eq $Private:TabSession.Id -and
                    [bool]$_.Context.Caller.IncludeDataObjectHtml -eq [bool]$IncludeDataObjectHtml
                }) | Select-Object -First 1

            if ($null -ne $Private:Outstanding) {
                "The SQL Troubleshooting view is already being retrieved for this tab; joining that request rather than making a second one." | Write-LogOutput -LogType DEBUG
                return $Private:Outstanding
            }
        }

        # Both the caller's block and the caller's data travel on the context, and are read back from
        # it in the completion. Invoke-OmadaPSWebRequestWrapperAsync nests whatever is passed here
        # under .Caller, so these are reached as $Pending.Context.Caller.OnResult / .Context.
        return Invoke-OmadaPSWebRequestWrapperAsync -Description $Script:SqlTroubleShooterViewRequestDescription -Context @{
            OnResult              = $OnResultScriptBlock
            Context               = $Context
            # Recorded so the in-flight guard above can tell whether an outstanding lookup is the
            # same SHAPE, not merely the same description on the same tab.
            IncludeDataObjectHtml = [bool]$IncludeDataObjectHtml
        } -PipelineContext @{
            PipelineFunction      = "Invoke-OmadaViewLookupPipeline"
            PipelineFiles         = @("New-OmadaPagingRequest.ps1", "Invoke-OmadaViewLookupPipeline.ps1")
            BaseUrl               = $Script:AppConfig.BaseUrl
            IncludeDataObjectHtml = [bool]$IncludeDataObjectHtml
            SqlQueryDoIdField     = $Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryDoId
        } -OnResultScriptBlock {
            param($Pending)

            $Private:Outcome = $Pending.Outcome

            # Replay what the worker would have logged, at the levels it chose. Without this, moving
            # the lookup off the UI thread would silently cost this application the log lines it has
            # always written for these two requests.
            if ($null -ne $Private:Outcome -and $Private:Outcome -isnot [System.Management.Automation.ErrorRecord]) {
                Write-ExecutePipelineLog -Log $Private:Outcome.Log
            }

            # What a failure MEANS is Resolve-ExecuteFallbackAction's decision, not this function's.
            # Classifying it here instead - "no completed steps, so the worker is broken" - would
            # reintroduce precisely the bug that function was written to fix: a tenant can answer
            # with an HTTP error on the FIRST step (401, 403, 502), which leaves CompletedSteps at 0
            # even though the worker plainly reached the tenant. That misreading once disabled
            # background execution for a whole session over one transient 502.
            #
            # A status code proves the worker worked. That reasoning belongs in one place, and this
            # is a second pipeline arriving at the same question - so it asks rather than re-deciding.
            if ($null -eq $Private:Outcome -or $Private:Outcome -is [System.Management.Automation.ErrorRecord] -or $null -ne $Private:Outcome.ErrorRecord) {
                # An ErrorRecord rather than an outcome means the wrapper classified a tenant-level
                # failure. Presented in the shape the classifier reads, so it sees the failure itself
                # rather than an object with no ErrorRecord - which it would read as "nothing came
                # back at all".
                $Private:Classifiable = if ($Private:Outcome -is [System.Management.Automation.ErrorRecord]) {
                    @{ ErrorRecord = $Private:Outcome; CompletedSteps = 0 }
                }
                else {
                    $Private:Outcome
                }

                $Private:Failure = $Private:Classifiable.ErrorRecord
                $Private:Reason = if ($null -eq $Private:Failure) { "the background worker returned no result" } else { $Private:Failure.Exception.Message }
                $Private:Action = Resolve-ExecuteFallbackAction -Outcome $Private:Classifiable

                if ($Private:Action -eq "Report" -or -not $Script:ConnectionStatus) {
                    # The tenant answered, and re-running inline would send the identical request and
                    # get the identical answer. The caller's own "no rows" handling is what that means.
                    "Could not retrieve the SQL Troubleshooting view: {0}" -f $Private:Reason | Write-LogOutput -LogType WARNING -SkipDialog
                    & $Pending.Context.Caller.OnResult @{ Rows = $null; DataObjectHtml = $null; RetryInline = $false } $Pending.Context.Caller.Context
                    return
                }

                "The SQL Troubleshooting view could not be retrieved on a background worker: {0}" -f $Private:Reason | Write-LogOutput -LogType DEBUG

                # Only on RetryAndDisable. Disabling is a one-way door for the session, so a 401 -
                # which is Retry - must not take it: the UI thread signs in, and the worker then has
                # a session to inherit.
                if ($Private:Action -eq "RetryAndDisable") {
                    Disable-OmadaBackgroundRequest -Reason $Private:Reason
                }

                # RetryInline rather than calling Get-SqlTroubleShooterView here: the caller's
                # synchronous path may be more than this lookup (Update-DataConnectionList follows it
                # with its own request), and it already exists for the not-dispatched case. Sending
                # the caller down that same path keeps one definition of it instead of two that can
                # drift.
                #
                # Safe to retry whatever the cause: both round-trips are reads, so running them again
                # changes nothing on the tenant.
                "The SQL Troubleshooting view lookup will be retried on the UI thread." | Write-LogOutput -LogType DEBUG
                & $Pending.Context.Caller.OnResult @{ Rows = $null; DataObjectHtml = $null; RetryInline = $true } $Pending.Context.Caller.Context
                return
            }

            & $Pending.Context.Caller.OnResult @{
                Rows           = $Private:Outcome.Rows
                DataObjectHtml = $Private:Outcome.DataObjectHtml
                RetryInline    = $false
            } $Pending.Context.Caller.Context
        }
    }
    catch {
        "Could not start the SQL Troubleshooting view lookup on a background worker; it will run on the UI thread. {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        return $null
    }
}
