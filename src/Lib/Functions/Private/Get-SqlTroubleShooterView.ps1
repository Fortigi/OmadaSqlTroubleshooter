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
            $View = $ViewResult.d.Rows | Where-Object { $_.Name -eq "SQL Troubleshooting" }
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
            $Private:Result = $Private:Result.d.Rows
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
        $Private:TabSession = Get-ActiveTabSession
        if ($null -ne $Private:TabSession -and @($Script:PendingWebViewCompletions | Where-Object {
                    $_.Description -eq $Script:SqlTroubleShooterViewRequestDescription -and
                    $_.TabSession.Id -eq $Private:TabSession.Id
                }).Count -gt 0) {
            "The SQL Troubleshooting view is already being retrieved for this tab; not requesting it twice." | Write-LogOutput -LogType DEBUG
            return $null
        }

        # Both the caller's block and the caller's data travel on the context, and are read back from
        # it in the completion. Invoke-OmadaPSWebRequestWrapperAsync nests whatever is passed here
        # under .Caller, so these are reached as $Pending.Context.Caller.OnRows / .Context.
        return Invoke-OmadaPSWebRequestWrapperAsync -Description $Script:SqlTroubleShooterViewRequestDescription -Context @{
            OnResult = $OnResultScriptBlock
            Context  = $Context
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

            # A worker that could not run the lookup at all is not an answer. Retry once inline,
            # where authentication works - the same fallback, and the same reasoning, as the schema
            # fetch: both round-trips are reads, so running them again changes nothing on the tenant.
            #
            # CompletedSteps distinguishes "could not reach the tenant" from "the tenant refused
            # something". Only the first is worth retrying; a tenant that answered will answer the
            # same way again.
            $Private:WorkerFailed = ($null -eq $Private:Outcome -or
                $Private:Outcome -is [System.Management.Automation.ErrorRecord] -or
                ($null -ne $Private:Outcome.ErrorRecord -and $Private:Outcome.CompletedSteps -eq 0))

            if ($Private:WorkerFailed -and $Script:ConnectionStatus) {
                $Private:Reason = if ($null -eq $Private:Outcome) {
                    "the background worker returned no result"
                }
                elseif ($Private:Outcome -is [System.Management.Automation.ErrorRecord]) {
                    $Private:Outcome.Exception.Message
                }
                else {
                    $Private:Outcome.ErrorRecord.Exception.Message
                }

                "The SQL Troubleshooting view could not be retrieved on a background worker: {0}" -f $Private:Reason | Write-LogOutput -LogType DEBUG
                Disable-OmadaBackgroundRequest -Reason $Private:Reason

                # RetryInline rather than calling Get-SqlTroubleShooterView here: the caller's
                # synchronous path may be more than this lookup (Update-DataConnectionList follows it
                # with its own request), and it already exists for the not-dispatched case. Sending
                # the caller down that same path keeps one definition of it instead of two that can
                # drift.
                "The SQL Troubleshooting view lookup will be retried on the UI thread." | Write-LogOutput -LogType DEBUG
                & $Pending.Context.Caller.OnResult @{ Rows = $null; DataObjectHtml = $null; RetryInline = $true } $Pending.Context.Caller.Context
                return
            }

            # The tenant answered and refused, or answered and holds no such view. Both are answers,
            # and the caller's own "no rows" handling is what they mean.
            if ($Private:Outcome -is [System.Management.Automation.ErrorRecord] -or $null -ne $Private:Outcome.ErrorRecord) {
                $Private:Failure = if ($Private:Outcome -is [System.Management.Automation.ErrorRecord]) { $Private:Outcome } else { $Private:Outcome.ErrorRecord }
                "Could not retrieve the SQL Troubleshooting view: {0}" -f $Private:Failure.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
                & $Pending.Context.Caller.OnResult @{ Rows = $null; DataObjectHtml = $null; RetryInline = $false } $Pending.Context.Caller.Context
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
