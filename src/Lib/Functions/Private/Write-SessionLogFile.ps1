function New-SessionLogFileState {
    <#
    .SYNOPSIS
        Creates the state the session log file is written through.

    .DESCRIPTION
        Created before anything can log, so the lines emitted during start-up - assembly loading,
        hash verification, the parser install, all the things that fail before the configuration
        file has even been read - are held and written to the file as soon as it opens. A session
        that dies during start-up is exactly the session somebody wants the log of.

        The buffer is bounded. If the file never opens at all, the held lines must not become
        unbounded growth; past the limit the oldest are kept, because the first failure explains the
        ones after it.

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

    return [PSCustomObject]@{
        StartTime      = Get-Date
        ProcessId      = $PID
        # Set when the file opens: the key depends on which other sessions are already in the folder.
        SessionKey     = $null
        LogLevel       = $LogLevel
        Directory      = $null
        Path           = $null
        # For the session writing OmadaSqlTroubleshooter.log, the number the active file receives when
        # it is split off. For a session writing numbered parts directly, the part being written.
        Part           = 1
        UsesActiveName = $false
        Writer         = $null
        BytesWritten   = [long]0
        MaxBytes       = [long]0
        Pending        = [System.Collections.Generic.List[PSCustomObject]]::new()
        PendingLimit   = 2000
        Failed         = $false
        # What Write-SessionLogFile locks on. TextWriter::Synchronized makes WriteLine atomic and
        # nothing else: BytesWritten, Part, Path and the Writer reference itself are all
        # read-modify-written around it, and a split disposes, renames and replaces the writer.
        SyncRoot       = [object]::new()
    }
}

function Open-SessionLogFileWriter {
    <#
    .SYNOPSIS
        Creates a new session log file part and opens the writer it is written through.

    .DESCRIPTION
        The properties of this handle are load-bearing:

          * FileMode.CreateNew, so an existing file is never overwritten or appended to by accident.
            -Append is the one exception, for reopening this session's own file when a split could
            not rename it.
          * FileShare.ReadWrite and NOT FileShare.Delete. Read and write sharing let a user open,
            copy or tail the file while the application is still writing it. Leaving Delete out is
            what makes "in use" detectable: on Windows a rename or a delete has to open the file with
            DELETE access, and a handle that did not share Delete refuses it. So another instance's
            attempt to rotate this live OmadaSqlTroubleshooter.log, or to prune a session still being
            written, fails in the operating system - atomically, with no window between checking and
            acting, and released by the OS the moment this process dies, crash included.
          * AutoFlush, so every line is on disk when the call that wrote it returns. Buffering would
            let a crash take the last and most interesting lines with it.
          * TextWriter::Synchronized, because a StreamWriter is not thread-safe. The state around it
            is guarded by the state's SyncRoot.

        A new part starts with the header from Get-SessionLogFileHeader, which is the only line that
        reaches this file without passing through Write-SessionLogFile.

    .PARAMETER Path
        The file to create, or with -Append to reopen.

    .PARAMETER SessionKey
        The session key recorded in the header.

    .PARAMETER StartTime
        The session start recorded in the header.

    .PARAMETER ProcessId
        The process id recorded in the header.

    .PARAMETER Append
        Reopen an existing file of this session instead of creating one. No header is written.

    .OUTPUTS
        [PSCustomObject] with Writer and BytesWritten (the header's size).

    .NOTES
        No tracer preamble: on the logging path.
    #>

    [CmdLetBinding(DefaultParameterSetName = "New")]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,
        [Parameter(Mandatory = $true, ParameterSetName = "New")]
        [string]$SessionKey,
        [Parameter(Mandatory = $true, ParameterSetName = "New")]
        [datetime]$StartTime,
        [Parameter(Mandatory = $true, ParameterSetName = "New")]
        [int]$ProcessId,
        [Parameter(Mandatory = $true, ParameterSetName = "Append")]
        [switch]$Append
    )

    # FileMode.Open and a seek for -Append, not FileMode.Append: FileMode.Append creates a file that
    # does not exist, and a part created that way would have no header. Reopening must only ever
    # reopen; a missing file throws, and the caller creates a proper part instead.
    $FileMode = [System.IO.FileMode]::CreateNew
    if ($Append) {
        $FileMode = [System.IO.FileMode]::Open
    }

    $Stream = [System.IO.FileStream]::new($Path, $FileMode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try {
        if ($Append) {
            $Stream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
        }

        # No byte order mark, matching what "Export Log File" writes.
        $Writer = [System.IO.StreamWriter]::new($Stream, [System.Text.UTF8Encoding]::new($false))
        $Writer.AutoFlush = $true

        $BytesWritten = [long]0
        if (-not $Append) {
            $Header = Get-SessionLogFileHeader -SessionKey $SessionKey -StartTime $StartTime -ProcessId $ProcessId
            $Writer.WriteLine($Header)
            $BytesWritten = [long]([System.Text.Encoding]::UTF8.GetByteCount($Header) + [System.Text.Encoding]::UTF8.GetByteCount([System.Environment]::NewLine))
        }
    }
    catch {
        $Stream.Dispose()
        throw
    }

    return [PSCustomObject]@{
        Writer       = [System.IO.TextWriter]::Synchronized($Writer)
        BytesWritten = $BytesWritten
    }
}

function Enter-SessionLogFileMutex {
    <#
    .SYNOPSIS
        Takes the machine-wide lock that serializes changes to one session log folder.

    .DESCRIPTION
        Share modes make each rename and delete safe on its own. This makes the sequences around them
        safe: choosing a session key that no other session holds, rotating the leftover active file,
        pruning, and splitting a part off. Without it, two instances starting in the same second could
        both pick the same key before either had a file on disk.

        Named for the folder, so two folders never block each other, and in the Local namespace, which
        needs no privilege. The OS releases it if its holder dies; that arrives here as an abandoned
        mutex, which is still a lock acquired.

        A lock that cannot be had within the timeout returns nothing and the caller carries on
        without it. Logging must never stall behind another process, and CreateNew and
        move-without-overwrite still guarantee no file is ever replaced.

    .PARAMETER Directory
        The session log folder.

    .PARAMETER TimeoutMilliseconds
        How long to wait.

    .OUTPUTS
        [System.Threading.Mutex] held by the caller, or nothing.

    .NOTES
        No tracer preamble: on the logging path. A mutex belongs to the thread that took it, so the
        caller releases it with Exit-SessionLogFileMutex in the same call.
    #>

    [CmdLetBinding()]
    [OutputType([System.Threading.Mutex])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory,
        [Parameter(Mandatory = $false)]
        [int]$TimeoutMilliseconds = 10000
    )

    try {
        $NormalizedDirectory = [System.IO.Path]::GetFullPath($Directory).TrimEnd([char[]]@('\', '/')).ToUpperInvariant()
        $Hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $DirectoryHash = [System.BitConverter]::ToString($Hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($NormalizedDirectory))) -replace "-", ""
        }
        finally {
            $Hasher.Dispose()
        }

        $Mutex = [System.Threading.Mutex]::new($false, ("Local\OmadaSqlTroubleshooter.SessionLog.{0}" -f $DirectoryHash))
    }
    catch {
        $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: could not create the session log folder lock: {0}" -f $_.Exception.Message))
        return $null
    }

    $Acquired = $false
    try {
        $Acquired = $Mutex.WaitOne($TimeoutMilliseconds)
    }
    catch {
        if ($_.Exception -is [System.Threading.AbandonedMutexException] -or $_.Exception.InnerException -is [System.Threading.AbandonedMutexException]) {
            $Acquired = $true
        }
    }

    if (-not $Acquired) {
        $Mutex.Dispose()
        $Script:Tracer::WriteLine("OmadaSqlTroubleshooter: continuing without the session log folder lock")
        return $null
    }

    return $Mutex
}

function Exit-SessionLogFileMutex {
    <#
    .SYNOPSIS
        Releases a lock taken with Enter-SessionLogFileMutex.

    .PARAMETER Mutex
        The lock, or nothing when none was taken.

    .NOTES
        No tracer preamble: on the logging path.
    #>

    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [System.Threading.Mutex]$Mutex
    )

    if ($null -eq $Mutex) {
        return
    }

    try {
        $Mutex.ReleaseMutex()
    }
    catch {
        $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: could not release the session log folder lock: {0}" -f $_.Exception.Message))
    }

    $Mutex.Dispose()
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
        of issues #39 and #111.

        Two callers, and only two, both of which satisfy that:

          * Write-LogOutput, immediately AFTER the gate has masked the message;
          * Start-SessionLogFile, replaying the lines held before the file could be opened - which
            reached the buffer through Write-LogOutput, and therefore through the gate.

        SessionLogFileRedaction.Tests.ps1 asserts exactly that set. A third caller, or a different
        argument in the second, is a message reaching disk unmasked.

        The file applies its OWN level: the log window and the file filter differently, and the
        window's decision has already been made by the time this is called.

        When the part reaches the size limit it is split off after the line that crossed it, under
        the same lock the line was written under, so the next line - from any thread - lands in the
        new part: nothing lost, nothing written twice.

        Nothing in here throws. A failure disables the file for the rest of the session and says so
        through the tracer rather than through the log it has just lost the ability to write.

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
        # turn one write into two I/O operations. WriteLine ends the line with Environment.NewLine,
        # so that is what is counted, rather than assuming it is "`r`n".
        $State.BytesWritten += [System.Text.Encoding]::UTF8.GetByteCount($Line) + [System.Text.Encoding]::UTF8.GetByteCount([System.Environment]::NewLine)

        # Part 999 is the last number a name can carry, so the last part simply keeps growing:
        # logging never stops because of size.
        if ($State.MaxBytes -gt 0 -and $State.BytesWritten -ge $State.MaxBytes -and $State.Part -lt 999) {
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
        # A lock a failed write kept would freeze every later log line.
        if ($LockTaken) {
            [System.Threading.Monitor]::Exit($State.SyncRoot)
        }
    }
}

function Switch-SessionLogFilePart {
    <#
    .SYNOPSIS
        Splits the session log file into a finished part and a fresh one.

    .DESCRIPTION
        The part being written by the session that owns OmadaSqlTroubleshooter.log is closed, renamed
        to OmadaSqlTroubleshooter_<session>_<NNN>.log, and a fresh OmadaSqlTroubleshooter.log is
        created in its place. A session writing numbered parts directly - a second instance - closes
        its part and creates the next number.

        Closing before renaming is required, not tidy: this handle does not share Delete, so the
        rename would be refused while it is open - the same protection that stops another instance
        renaming it.

        If the rename is refused anyway - a user's editor holding the file without Delete sharing - the
        same file is reopened for append and the split is tried again after another limit's worth of
        lines. Nothing is lost either way.

    .NOTES
        No tracer preamble: on the logging path. Called only from Write-SessionLogFile, inside its
        lock and its try, so a failure here is handled like any other write failure.
    #>

    [CmdLetBinding()]
    param()

    $State = $Script:SessionLogFile
    if ($null -eq $State -or $null -eq $State.Writer) {
        return
    }

    $Mutex = Enter-SessionLogFileMutex -Directory $State.Directory
    try {
        $State.Writer.Dispose()
        $State.Writer = $null

        if ($State.UsesActiveName) {
            $Finished = Get-AvailableSessionLogFilePart -Directory $State.Directory -SessionKey $State.SessionKey -Part $State.Part
            $Renamed = $false
            if ($null -ne $Finished) {
                try {
                    [System.IO.File]::Move($State.Path, $Finished.Path)
                    $Renamed = $true
                }
                catch {
                    $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: could not split the session log file, still writing '{0}': {1}" -f $State.Path, $_.Exception.Message))
                }
            }

            if (-not $Renamed) {
                if ([System.IO.File]::Exists($State.Path)) {
                    $Opened = Open-SessionLogFileWriter -Path $State.Path -Append
                    $State.Writer = $Opened.Writer
                    $State.BytesWritten = [long]0
                    return
                }

                # The file vanished between closing it and renaming it - nothing holds it in that
                # instant, so somebody could delete it. Start it again as a proper part, header
                # first, so rotation and pruning still know which session it belongs to.
                $Opened = Open-SessionLogFileWriter -Path $State.Path -SessionKey $State.SessionKey -StartTime $State.StartTime -ProcessId $State.ProcessId
                $State.Writer = $Opened.Writer
                $State.BytesWritten = $Opened.BytesWritten
                return
            }

            $State.Part = $Finished.Part + 1
            try {
                $Opened = Open-SessionLogFileWriter -Path $State.Path -SessionKey $State.SessionKey -StartTime $State.StartTime -ProcessId $State.ProcessId
                $State.Writer = $Opened.Writer
                $State.BytesWritten = $Opened.BytesWritten
                return
            }
            catch {
                # Something else created the active name in the instant it was free. That file is not
                # this session's, so it is left alone and the session continues in numbered parts.
                $State.UsesActiveName = $false
                $State.Part = $Finished.Part
            }
        }

        $Next = Get-AvailableSessionLogFilePart -Directory $State.Directory -SessionKey $State.SessionKey -Part ($State.Part + 1)
        if ($null -eq $Next) {
            throw "no part number is left for session {0}" -f $State.SessionKey
        }

        $Opened = Open-SessionLogFileWriter -Path $Next.Path -SessionKey $State.SessionKey -StartTime $State.StartTime -ProcessId $State.ProcessId
        $State.Path = $Next.Path
        $State.Part = $Next.Part
        $State.Writer = $Opened.Writer
        $State.BytesWritten = $Opened.BytesWritten
    }
    finally {
        Exit-SessionLogFileMutex -Mutex $Mutex
    }
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

        The file keeps its name. The next session to start renames it to its numbered part, which is
        also what happens to the file a crashed session leaves behind - one path for both.

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
