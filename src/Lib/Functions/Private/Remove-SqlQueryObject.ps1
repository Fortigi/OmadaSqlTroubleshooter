function Remove-SqlQueryObject {
    <#
    .SYNOPSIS
    Delete a query object by DoId. Runs on a background worker when one is available.

    .DESCRIPTION
    This is a fire-and-forget clean-up: nothing in the app waits on its result, and every caller
    already treats a failure as a warning rather than an error. That makes it the easiest of the
    execute path's round-trips to take off the UI thread (issue #40, C1-5), and the one it matters
    most for - it is what runs when the user clicks Cancel, and blocking the UI thread inside the
    handler that exists to unblock the UI would be a poor joke.

    Falls back to a synchronous delete when no worker is available, exactly as every other
    background caller does.

    .PARAMETER Synchronous
    Delete before returning, instead of dispatching and returning immediately.

    Required on the cancel path, where fire-and-forget is not safe. The temporary object is named
    TMP_<InstanceGuid> - one name for the whole application instance - and the execute pipeline
    probes for it and REUSES it rather than creating a new one, so the same DoId comes back on every
    execute-selection. An asynchronous delete left in flight by a cancel can therefore land after the
    user has started another execute-selection and delete the object that execution is using.

    The window is only a few hundred milliseconds, but "cancel, then immediately run it again" is
    exactly what a user does, so it is the likely case rather than an unlikely one.

    .PARAMETER DoId
    The query object to delete.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DoId,

        [switch]$Synchronous
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        "Deleting query object with DoId: {0}" -f $DoId | Write-LogOutput -LogType DEBUG

        # The same builder the pipeline uses in the worker, so there is one definition of this URL.
        $Private:Request = New-OmadaQueryRequest -Kind "DeleteQuery" -Context @{
            BaseUrl       = $Script:AppConfig.BaseUrl
            TempQueryDoId = $DoId
        }

        $Script:RunTimeData.RestMethodParam.Uri = $Private:Request.Uri
        $Script:RunTimeData.RestMethodParam.Method = $Private:Request.Method
        $Script:RunTimeData.RestMethodParam.Body = $Private:Request.Body

        "QueryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG

        # -Synchronous skips the dispatch entirely rather than dispatching and waiting: the caller
        # needs the object gone before anything else can claim its DoId, and the only way to promise
        # that is to do it here. See the parameter's help for why the cancel path needs it.
        if (-not $Synchronous) {
            $Private:Pending = Invoke-OmadaPSWebRequestWrapperAsync -Description "Delete query object" -Context @{ DoId = $DoId } -OnResultScriptBlock {
                param($Pending)
                if ($Pending.Outcome -is [System.Management.Automation.ErrorRecord]) {
                    "Failed to delete query object {0}: {1}" -f $Pending.Context.Caller.DoId, $Pending.Outcome.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
                    return
                }
                "Query object {0} deleted successfully." -f $Pending.Context.Caller.DoId | Write-LogOutput -LogType DEBUG
            }

            if ($null -ne $Private:Pending) {
                return
            }
        }

        # The result is inspected, not discarded. Invoke-OmadaPSWebRequestWrapper THROWS only for the
        # two classified tenant failures; an unclassified one comes back as an ErrorRecord, so piping
        # to Out-Null and logging success below reported a deletion that had not happened.
        #
        # That is worse here than a wrong log line. This is the path -Synchronous exists for: the
        # cancel path, where the caller needs the TMP_<guid> object gone before anything can claim its
        # DoId. A false "deleted successfully" leaves the object on the tenant and says otherwise -
        # in a troubleshooting tool, whose log is the thing a user reaches for.
        #
        # The asynchronous branch above already got this right; this is the same check.
        $Private:Result = Invoke-OmadaPSWebRequestWrapper
        if ($Private:Result -is [System.Management.Automation.ErrorRecord]) {
            "Failed to delete query object {0}: {1}" -f $DoId, $Private:Result.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
            return
        }

        "Query object {0} deleted successfully." -f $DoId | Write-LogOutput -LogType DEBUG
    }
    catch {
        "Failed to delete query object {0}: {1}" -f $DoId, $_.Exception.Message | Write-LogOutput -LogType WARNING
    }
}
