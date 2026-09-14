function Start-SessionLogFile {
    <#
    .SYNOPSIS
        Opens this session's log file, prunes the old ones, and flushes what was held during
        start-up.

    .DESCRIPTION
        Called once, from Invoke-OmadaSqlTroubleshooter, as soon as the global configuration has
        been read - because the configuration is what says whether a file is wanted at all, where it
        goes, which level it runs at and how much of it is kept.

        Everything logged before that point was held by Write-SessionLogFile and is written here,
        against the level this function resolves rather than the provisional one. Start-up is where
        an application dies, so those lines are the ones most worth having.

        Pruning runs BEFORE the file is opened, and is told to leave this session alone. Both halves
        matter: pruning afterwards would let a session with a tight retention delete its own log,
        and pruning without the exclusion would do it deliberately.

        A file that cannot be opened is not a reason to fail the start-up path. The application runs
        without one, exactly as it did before this feature existed, and says so once.

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
            # lines held during start-up go with it, which is the point of switching it off.
            $Script:SessionLogFile = $null
            return
        }

        $State = $Script:SessionLogFile
        if ($null -eq $State) {
            $State = New-SessionLogFileState -LogLevel $Setting.LogLevel
        }

        $State.LogLevel = $Setting.LogLevel
        $State.Directory = $Setting.Directory
        $State.MaxBytes = [long]$Setting.MaxSizeMegabytes * 1MB

        New-Item -Path $Setting.Directory -ItemType Directory -Force -ErrorAction Stop | Out-Null

        Remove-ExpiredSessionLogFile -Directory $Setting.Directory -RetentionDays $Setting.RetentionDays -RetentionCount $Setting.RetentionCount -ExcludeSession $State.SessionKey | Out-Null

        $State.Path = Join-Path $Setting.Directory -ChildPath (Get-SessionLogFileName -StartTime $State.StartTime -ProcessId $State.ProcessId -Part $State.Part)
        $State.Writer = Open-SessionLogFileWriter -Path $State.Path
        $Script:SessionLogFile = $State

        # Clearing Pending first is deliberate: Write-SessionLogFile holds a line whenever Pending is
        # a list, so flushing into itself would put every held line straight back into the buffer.
        $Pending = $State.Pending
        $State.Pending = $null
        foreach ($Entry in $Pending) {
            Write-SessionLogFile -Line $Entry.Line -LogType $Entry.LogType
        }

        # Through Write-LogOutput, so it reaches the log window as well as the file: the path is how
        # a user finds the log without being told where to look, and the log window's own link is
        # only useful to somebody who has already opened the log window.
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
