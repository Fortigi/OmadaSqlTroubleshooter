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
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DoId
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

        Invoke-OmadaPSWebRequestWrapper | Out-Null
        "Query object {0} deleted successfully." -f $DoId | Write-LogOutput -LogType DEBUG
    }
    catch {
        "Failed to delete query object {0}: {1}" -f $DoId, $_.Exception.Message | Write-LogOutput -LogType WARNING
    }
}
