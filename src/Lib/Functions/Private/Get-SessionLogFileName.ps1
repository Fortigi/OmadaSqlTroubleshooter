function Get-SessionLogFileName {
    <#
    .SYNOPSIS
        Builds the file name for one part of one session's log file.

    .DESCRIPTION
        The name answers the two questions somebody asks of a folder full of logs - when did this
        session start, and which process wrote it - and carries a part number, because a session
        that reaches the configured size ceiling rolls into a new file rather than stopping.

        The process id is what keeps parallel instances apart: two copies of the application started
        in the same second would otherwise write to one file.

    .PARAMETER StartTime
        When the session started. The same value for every part of one session, so all of a
        session's parts share a session key.

    .PARAMETER ProcessId
        The id of the process writing the file.

    .PARAMETER Part
        The 1-based part number. Zero-padded so the parts of one session sort in the order they were
        written.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-SessionLogFileName -StartTime (Get-Date) -ProcessId $PID
        OmadaSqlTroubleshooter_20260914-080503_pid4242_001.log

    .NOTES
        No tracer preamble: called from the logging path, which must not log about itself.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [datetime]$StartTime,
        [Parameter(Mandatory = $true, Position = 1)]
        [int]$ProcessId,
        [Parameter(Mandatory = $false, Position = 2)]
        [int]$Part = 1
    )

    return "OmadaSqlTroubleshooter_{0}_pid{1}_{2:000}.log" -f $StartTime.ToString("yyyyMMdd-HHmmss"), $ProcessId, $Part
}

function Get-SessionLogFilePattern {
    <#
    .SYNOPSIS
        The wildcard pattern that enumerates session log files, and only session log files.

    .DESCRIPTION
        Pruning deletes what this finds, so it must never widen to a file the application did not
        write. A user is entitled to keep their own notes in the log folder.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param()

    return "OmadaSqlTroubleshooter_*_pid*_*.log"
}

function Get-SessionLogFileNameExpression {
    <#
    .SYNOPSIS
        The expression that splits a session log file name into its session key and its part.

    .DESCRIPTION
        Retention counts SESSIONS, not files, so the parts of one long session have to group back
        together before anything is counted or deleted. The Session capture is that grouping key;
        the Part capture orders the parts within it.

        Stricter than the wildcard pattern on purpose: the wildcard is what the file system can
        filter on cheaply, this is what decides whether a candidate really is one of ours.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param()

    return '^OmadaSqlTroubleshooter_(?<Session>\d{8}-\d{6}_pid\d+)_(?<Part>\d{3})\.log$'
}
