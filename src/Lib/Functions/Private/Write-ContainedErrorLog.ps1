function Write-ContainedErrorLog {
    <#
    .SYNOPSIS
    Report an error to the user exactly as Write-LogOutput -LogType ERROR does, without letting the
    reporting itself unwind the caller.

    .DESCRIPTION
    Write-LogOutput ends every ERROR with "Write-Error", and this application runs with
    $ErrorActionPreference = Stop. So logging an ERROR is TERMINATING: it throws.

    That is deliberate and long-standing - it is how an error propagates out to a caller that should
    stop - and code which logs an ERROR as the last statement of a catch block relies on it. It is
    also a trap anywhere else, and it caused a real one: reporting a tenant failure from a completion
    block threw, the completion's own catch logged the throw as another ERROR, which threw again, the
    poll timer's catch logged THAT, and the dispatcher's unhandled handler logged the result - five
    stacked error dialogs and a log entry containing four nested copies of itself, for one HTTP 500.

    A completion block is invoked by a timer. There is no caller to unwind to and nothing useful
    above it, so an error reported from one must be reported and contained. That is what this does:
    the user still gets the message and the dialog, exactly once, and control returns normally.

    Use this wherever an error is reported from a completion block, or from anywhere that must carry
    on afterwards. Keep using Write-LogOutput -LogType ERROR directly where the throw is wanted.

    .PARAMETER Message
    The message to report.

    .PARAMETER ErrorObject
    The originating error, passed through for the call stack Write-LogOutput records.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        $ErrorObject
    )

    process {
        try {
            $Message | Write-LogOutput -LogType ERROR -ErrorObject $ErrorObject
        }
        catch {
            # Expected, and the entire point: Write-LogOutput has already written the line and shown
            # the dialog by the time it throws. Swallowing it here is what stops one error becoming
            # a cascade of them. Nothing is lost - the message has been reported.
        }
    }
}
