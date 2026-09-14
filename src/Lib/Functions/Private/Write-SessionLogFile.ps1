function New-SessionLogFileState {
    <#
    .SYNOPSIS
        Creates the state the session log file is written through.

    .DESCRIPTION
        Created before anything can log, so the lines emitted during start-up - assembly loading,
        hash verification, the parser install, all the things that fail before the configuration
        file has even been read - are held and written to the file as soon as it opens. A session
        that dies during start-up is exactly the session somebody wants the log of.

        The buffer is bounded. If the file never opens at all, the held lines must not become the
        unbounded growth this feature exists to stop; past the limit the oldest are kept, because
        the first failure explains the ones after it.

    .PARAMETER LogLevel
        The provisional level, used only until Start-SessionLogFile resolves the configured one.
        Held lines are re-filtered against the resolved level when they are written, so this value
        never decides what ends up in the file.

    .OUTPUTS
        [PSCustomObject]

    .NOTES
        No tracer preamble: everything in this file is on the path Write-LogOutput takes for every
        message, so logging from here would recurse.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$LogLevel = "DEBUG"
    )

    $StartTime = Get-Date

    return [PSCustomObject]@{
        StartTime    = $StartTime
        ProcessId    = $PID
        SessionKey   = "{0}_pid{1}" -f $StartTime.ToString("yyyyMMdd-HHmmss"), $PID
        LogLevel     = $LogLevel
        Directory    = $null
        Path         = $null
        Part         = 1
        Writer       = $null
        BytesWritten = [long]0
        MaxBytes     = [long]0
        Pending      = [System.Collections.Generic.List[PSCustomObject]]::new()
        PendingLimit = 2000
        Failed       = $false
        # What Write-SessionLogFile locks on. TextWriter::Synchronized makes WriteLine atomic and
        # nothing else: BytesWritten, Part, Path and the Writer reference itself are all
        # read-modify-written around it, and a rollover disposes and replaces the writer. Two
        # threads rolling at once could lose lines or dispose the writer out from under a write in
        # flight, abandoning the file for the rest of the session.
        SyncRoot     = [object]::new()
    }
}

function Open-SessionLogFileWriter {
    <#
    .SYNOPSIS
        Opens the writer one part of the session log file is written through.

    .DESCRIPTION
        Three properties of this handle are load-bearing:

          * AutoFlush, so every line is on disk when the call that wrote it returns. Buffering would
            reintroduce the problem the file exists to solve - a crash would take the last and most
            interesting lines with it.
          * FileShare.ReadWrite|Delete, so the user can open, copy or even delete the file while the
            application is still running. A log nobody can read until the application exits is the
            old behaviour under a new name.
          * TextWriter::Synchronized, because a StreamWriter is not thread-safe. That covers the
            writer itself and nothing around it - the state beside it is guarded by the state's
            SyncRoot, which Write-SessionLogFile, Start-SessionLogFile and Stop-SessionLogFile all
            take. Both, because this handle can outlive the state object that produced it.

    .PARAMETER Path
        The file to append to.

    .OUTPUTS
        [System.IO.TextWriter]

    .NOTES
        No tracer preamble: on the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([System.IO.TextWriter])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    $Stream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))

    # No byte order mark, matching what "Export Log File" writes, so the two files are the same kind
    # of file.
    $Writer = [System.IO.StreamWriter]::new($Stream, [System.Text.UTF8Encoding]::new($false))
    $Writer.AutoFlush = $true

    return [System.IO.TextWriter]::Synchronized($Writer)
}

function Write-SessionLogFile {
    <#
    .SYNOPSIS
        Writes one already-redacted log line to the session log file.

    .DESCRIPTION
        The file half of issue #121. Every line it writes has been through Protect-LogMessage, and
        that is not an implementation detail but the whole design: the file is behind the redaction
        gate, never beside it. A writer that took its own copy of a message would put unredacted
        credentials, tokens, result data and query text on disk permanently, which is a regression
        of issues #39 and #111 and strictly worse than the problem this feature solves.

        Two callers, and only two, both of which satisfy that:

          * Write-LogOutput, immediately AFTER the gate has masked the message;
          * Start-SessionLogFile, replaying the lines held before the file could be opened - which
            reached the buffer through Write-LogOutput, and therefore through the gate.

        SessionLogFileRedaction.Tests.ps1 asserts exactly that set, and asserts that the second one
        passes buffered entries rather than anything composed on the spot. A third caller, or a
        different argument in the second, is a message reaching disk unmasked.

        The file applies its OWN level, which is why the level test is here rather than at the call
        site: the log window and the file filter differently, and the window's decision has already
        been made by the time this is called.

        Nothing in here throws. A log writer that can take the application down is worse than no log
        writer, so a failure disables the file for the rest of the session and says so through the
        tracer rather than through the log it has just lost the ability to write.

    .PARAMETER Line
        The finished, redacted log line - the same text that goes into AppLogObject.

    .PARAMETER LogType
        The type of the message, tested against the file's own level.

    .NOTES
        No tracer preamble, and this must never call Write-LogOutput: Write-LogOutput calls it for
        every single message, so either would recurse. The same rule governs Protect-LogMessage.
    #>

    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$Line,
        [Parameter(Mandatory = $true, Position = 1)]
        [AllowEmptyString()]
        [string]$LogType
    )

    $State = $Script:SessionLogFile
    if ($null -eq $State -or $State.Failed) {
        return
    }

    # The whole body, not just the WriteLine. The synchronized writer makes one WriteLine atomic and
    # promises nothing about the counter beside it, the part number, the path, or the dispose and
    # replace a rollover performs - and an unguarded rollover racing a write loses lines or abandons
    # the file. Uncontended, this costs nothing worth measuring; contended, it is what makes the
    # crash-survival guarantee true from more than one thread.
    $LockTaken = $false
    try {
        [System.Threading.Monitor]::Enter($State.SyncRoot, [ref]$LockTaken)

        if ($null -eq $State.Writer) {
            # Not open yet. Hold the line WITH its type: the level the file will run at is not known
            # until the configuration has been read, so the filtering decision cannot be made here.
            # A $null Pending means the file has been stopped, and stopped is final.
            if ($null -ne $State.Pending -and $State.Pending.Count -lt $State.PendingLimit) {
                $State.Pending.Add([PSCustomObject]@{ LogType = $LogType; Line = $Line })
            }

            return
        }

        if (-not (Test-LogLevelThreshold -Level $State.LogLevel -LogType $LogType)) {
            return
        }

        $State.Writer.WriteLine($Line)
        # Counted rather than measured: asking the file system for its length on every line would
        # turn one write into two I/O operations. "`r`n" is two bytes in UTF-8.
        $State.BytesWritten += [System.Text.Encoding]::UTF8.GetByteCount($Line) + 2

        if ($State.MaxBytes -gt 0 -and $State.BytesWritten -ge $State.MaxBytes) {
            Switch-SessionLogFilePart
        }
    }
    catch {
        $State.Failed = $true
        try {
            $State.Writer.Dispose()
        }
        catch {}
        $State.Writer = $null
        $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: the session log file was abandoned: {0}" -f $_.Exception.Message))
    }
    finally {
        # A lock a failed write kept would freeze every later log line, which is a far worse failure
        # than the lost log file the catch above has already settled for.
        if ($LockTaken) {
            [System.Threading.Monitor]::Exit($State.SyncRoot)
        }
    }
}

function Switch-SessionLogFilePart {
    <#
    .SYNOPSIS
        Rolls the session log file into its next part when the current one reaches the ceiling.

    .DESCRIPTION
        A ceiling that simply stopped writing would discard the end of the session, which is the
        part a crash report is about - so the ceiling bounds the FILE, and the session continues in
        the next part. Retention then bounds the folder, counting sessions rather than files so one
        long session cannot evict every older one.

    .NOTES
        No tracer preamble: on the logging path. Called only from Write-SessionLogFile, inside its
        try, so a failure to roll is handled there like any other write failure.
    #>

    [CmdLetBinding()]
    param()

    $State = $Script:SessionLogFile
    if ($null -eq $State -or $null -eq $State.Writer) {
        return
    }

    $State.Writer.Dispose()
    $State.Writer = $null
    $State.Part = $State.Part + 1
    $State.Path = Join-Path $State.Directory -ChildPath (Get-SessionLogFileName -StartTime $State.StartTime -ProcessId $State.ProcessId -Part $State.Part)
    $State.Writer = Open-SessionLogFileWriter -Path $State.Path
    $State.BytesWritten = [long]0
}

function Stop-SessionLogFile {
    <#
    .SYNOPSIS
        Closes the session log file.

    .DESCRIPTION
        Tidiness rather than durability: every line was already flushed when it was written, so a
        session that never reaches this - a crash, a kill, a power cut - still leaves a complete
        file. What this adds is releasing the handle, and refusing anything written afterwards so
        the shutdown path cannot reopen a file that was deliberately closed.

        Safe to call twice, and safe to call when there is no file.

    .NOTES
        No tracer preamble: on the logging path.
    #>

    [CmdLetBinding()]
    param()

    $State = $Script:SessionLogFile
    if ($null -eq $State) {
        return
    }

    # Under the same lock Write-SessionLogFile takes, so shutdown cannot dispose the writer out from
    # under a line still being written.
    $LockTaken = $false
    try {
        [System.Threading.Monitor]::Enter($State.SyncRoot, [ref]$LockTaken)

        try {
            if ($null -ne $State.Writer) {
                $State.Writer.Dispose()
            }
        }
        catch {
            $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: the session log file did not close cleanly: {0}" -f $_.Exception.Message))
        }

        $State.Writer = $null
        # Both null together is what "stopped" means to Write-SessionLogFile: nothing to write to,
        # and nothing to hold lines in either.
        $State.Pending = $null
    }
    finally {
        if ($LockTaken) {
            [System.Threading.Monitor]::Exit($State.SyncRoot)
        }
    }
}
