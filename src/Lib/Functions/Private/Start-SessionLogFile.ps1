function Start-SessionLogFile {
    <#
    .SYNOPSIS
        Opens this session's log file when the configuration asks for one, rotates the previous one,
        prunes old sessions, and flushes what was held during start-up.

    .DESCRIPTION
        Called once, from Invoke-OmadaSqlTroubleshooter, as soon as the global configuration has
        been read - because the configuration is what says whether a file is wanted at all, where it
        goes, which level it runs at and how much of it is kept.

        Off by default. When EnableSessionLogFile is not true, nothing is created: no folder, no file,
        and the lines held during start-up are dropped with the state.

        When it is on, under the folder's lock (Enter-SessionLogFileMutex): Open-SessionLogFile
        rotates a free OmadaSqlTroubleshooter.log and opens this session's file, then
        Remove-ExcessSessionLogFile prunes to the retention count. Pruning runs after the file is
        opened, so the running session is one of the sessions counted.

        Everything logged before that point was held by Write-SessionLogFile and is written here,
        against the level this function resolves rather than the provisional one.

        A file that cannot be opened is not a reason to fail the start-up path. The application runs
        without one and says so once.

    .OUTPUTS
        [string] the path of the file that was opened, or nothing when no file is being written.

    .EXAMPLE
        Start-SessionLogFile

    .NOTES
        No tracer preamble: the tracer preamble logs, and this function runs while the log file is
        being set up.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param()

    try {
        $Setting = Get-LogFileSetting

        if (-not $Setting.Enabled) {
            # Nothing to write to, which is what Write-SessionLogFile reads as "not in play". Any
            # lines held during start-up go with it.
            $Script:SessionLogFile = $null
            return
        }

        $State = $Script:SessionLogFile
        if ($null -eq $State) {
            $State = New-SessionLogFileState -LogLevel $Setting.LogLevel
        }

        $Opened = $null

        # Under the state's own lock, the same one Write-SessionLogFile takes. Everything below
        # read-modify-writes state a concurrent line could also be touching, and the Pending handover
        # in particular has a window in which a line added to the old list would simply be lost.
        # Monitor is reentrant, so the Write-SessionLogFile calls in the flush below are fine.
        $LockTaken = $false
        try {
            [System.Threading.Monitor]::Enter($State.SyncRoot, [ref]$LockTaken)

            $State.LogLevel = $Setting.LogLevel
            $State.Directory = $Setting.Directory
            $State.MaxBytes = [long]$Setting.MaxSizeMegabytes * 1MB

            # Directory::CreateDirectory rather than New-Item, which has no -LiteralPath. The folder
            # is whatever the user typed, and "[" and "]" are wildcard characters to PowerShell's path
            # handling; this overload is literal by construction, and already idempotent.
            [System.IO.Directory]::CreateDirectory($Setting.Directory) | Out-Null

            # A session resuming after the "Write log file" checkbox was switched off and on again
            # (issue #138) keeps its own key, so its files stay one session to rotation, to pruning
            # and to anyone reading the folder. Failed is cleared with it: the state is about to be
            # given a working writer, and a stale flag would make Write-SessionLogFile drop every
            # line into the file that was just opened for it.
            $State.Failed = $false

            $Mutex = Enter-SessionLogFileMutex -Directory $Setting.Directory
            try {
                $Opened = Open-SessionLogFile -Directory $Setting.Directory -StartTime $State.StartTime -ProcessId $State.ProcessId -SessionKey $State.SessionKey

                $State.Path = $Opened.Path
                $State.Writer = $Opened.Writer
                $State.BytesWritten = $Opened.BytesWritten
                $State.SessionKey = $Opened.SessionKey
                $State.Part = $Opened.Part
                $State.UsesActiveName = $Opened.UsesActiveName
                $Script:SessionLogFile = $State

                Remove-ExcessSessionLogFile -Directory $Setting.Directory -RetentionCount $Setting.RetentionCount -CurrentSessionKey $State.SessionKey | Out-Null
            }
            finally {
                Exit-SessionLogFileMutex -Mutex $Mutex
            }

            # Clearing Pending first is deliberate: Write-SessionLogFile holds a line whenever
            # Pending is a list, so flushing into itself would put every held line straight back into
            # the buffer.
            $Pending = $State.Pending
            $State.Pending = $null
            foreach ($Entry in $Pending) {
                Write-SessionLogFile -Line $Entry.Line -LogType $Entry.LogType
            }
        }
        finally {
            if ($LockTaken) {
                [System.Threading.Monitor]::Exit($State.SyncRoot)
            }
        }

        if (![string]::IsNullOrWhiteSpace($Opened.RotatedPath)) {
            "The previous session log file was kept as: {0}" -f $Opened.RotatedPath | Write-LogOutput -LogType DEBUG
        }

        if (-not $Opened.UsesActiveName) {
            "{0} is in use, by another running instance or another program, so this session writes its own numbered file." -f (Get-SessionLogFileName) | Write-LogOutput -LogType INFO -SkipDialog
        }

        # Through Write-LogOutput, so it reaches the log window as well as the file: the path is how
        # a user finds the log without being told where to look.
        "Session log file: {0}" -f $State.Path | Write-LogOutput -LogType INFO -SkipDialog

        return $State.Path
    }
    catch {
        # Nulled BEFORE anything is logged: Write-LogOutput writes to the session log file, and the
        # state it would write through is the one that has just proved unusable.
        $Script:SessionLogFile = $null
        "No session log file will be written this session: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
    }
}
