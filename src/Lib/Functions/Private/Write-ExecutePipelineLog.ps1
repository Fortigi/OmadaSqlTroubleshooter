function Write-ExecutePipelineLog {
    <#
    .SYNOPSIS
    Replay the log entries a background worker recorded, on the UI thread, at the levels it chose.

    .DESCRIPTION
    Invoke-OmadaExecutePipeline runs in a worker runspace and cannot log: it has no $Script: state,
    no log file and no window. Without replaying what it did, moving the execute chain off the UI
    thread silently cost this application most of its diagnostic value - every URL, body, parameter
    set and response that used to appear in the log for an execute simply stopped being written down.
    For a tool whose purpose is troubleshooting, that is not an acceptable price for responsiveness.

    Redaction happens here rather than in the worker, and deliberately: ConvertTo-RedactedLogString
    is a UI-thread function and stays one, so there remains a single place that decides how much of a
    request or a response may be written down. The worker records WHAT to log; this decides what is
    safe to write.

    .PARAMETER Log
    Ordered entries from the pipeline's outcome. Each is either:
      @{ Level; Text }                          - a finished line
      @{ Level; Format; Redact; ShapeOnly }     - an object to redact and format into Format

    .NOTES
    Every entry is written with -SkipDialog. These are a replay of things that already happened, and
    a replayed line must never open a modal - a single execute records a dozen of them.
    #>
    [CmdLetBinding()]
    param(
        $Log
    )

    foreach ($Private:Entry in @($Log)) {
        try {
            if ($null -eq $Private:Entry) {
                continue
            }

            $Private:Level = if ([string]::IsNullOrWhiteSpace($Private:Entry.Level)) { "DEBUG" } else { $Private:Entry.Level }

            $Private:Text = $Private:Entry.Text
            if ($null -ne $Private:Entry.Format) {
                $Private:Text = $Private:Entry.Format -f (ConvertTo-RedactedLogString -InputObject $Private:Entry.Redact -ShapeOnly:([bool]$Private:Entry.ShapeOnly))
            }

            if ([string]::IsNullOrWhiteSpace($Private:Text)) {
                continue
            }

            $Private:Text | Write-LogOutput -LogType $Private:Level -SkipDialog
        }
        catch {
            # One unloggable entry - an object that will not redact, say - must not cost the log
            # every entry after it. Deliberately silent: this is itself the logging path, so
            # reporting the failure has nowhere useful to go.
            continue
        }
    }
}
