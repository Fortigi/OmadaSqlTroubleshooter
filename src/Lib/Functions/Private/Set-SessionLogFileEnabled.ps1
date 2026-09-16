function Set-SessionLogFileEnabled {
    <#
    .SYNOPSIS
        Single writer of the "write log file" option: persists it and starts or stops this session's
        log file straight away.

    .DESCRIPTION
        Issue #138. The file was off by default and switchable only by hand-editing
        EnableSessionLogFile, which is of no use to the person who needs a log most - the one
        reproducing a problem right now, who would have to close the application and lose the session
        they wanted to capture.

        The order is load-bearing. The setting is persisted FIRST, because Start-SessionLogFile asks
        Get-LogFileSetting whether a file is wanted at all, and that reads $Script:AppGlobalConfig -
        which is what Set-ConfigProperty updates. Starting before persisting would read the old value
        and do nothing.

        Switching it on while a file is already open does nothing: Open-LogForm reflects the resolved
        setting in the checkbox, and a handler that started a second file for that would rotate the
        first one for no reason.

        Switching it off closes the writer through Stop-SessionLogFile and then clears Path and
        Directory, so every reader of $Script:SessionLogFile - the log window's label, the Folder
        button, the "show request body" warning - says what is true: nothing is being written. What
        is deliberately kept is StartTime, ProcessId and SessionKey, which is how switching it on
        again continues this session rather than starting a second one in the folder.

        Known limitation, stated in the checkbox's tooltip: a file started mid-session holds only
        what is logged from that moment on. Lines logged before are gone - Start-SessionLogFile drops
        the start-up buffer when logging is off - and Export Log File still saves what the window
        holds.

    .PARAMETER Enabled
        Whether a session log file should be written.

    .OUTPUTS
        [bool] whether a file is being written when this returns. False after switching it off, and
        false when switching it on could not open one.

    .EXAMPLE
        Set-SessionLogFileEnabled -Enabled $true
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [bool]$Enabled
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        # Before anything is started or stopped: this is the value Get-LogFileSetting will read, and
        # it is also the whole of "the choice applies at the next start".
        $Enabled | Set-ConfigProperty -Property "EnableSessionLogFile"

        $State = $Script:SessionLogFile

        if ($Enabled) {
            if ($null -ne $State -and $null -ne $State.Writer) {
                "A session log file is already being written: {0}" -f $State.Path | Write-LogOutput -LogType DEBUG
                return $true
            }

            # Everything the start-up path does, and for the same reasons: the folder, the leftover
            # active file, the second-instance name, retention, and a warning instead of a failure
            # when the file cannot be opened.
            Start-SessionLogFile | Out-Null

            return ($null -ne $Script:SessionLogFile -and $null -ne $Script:SessionLogFile.Writer)
        }

        if ($null -eq $State) {
            return $false
        }

        $ClosedPath = $State.Path

        # Under the state's own lock, the one Write-SessionLogFile takes, so a line being written on
        # another thread cannot have the writer disposed out from under it - and so nothing reads a
        # Path that is about to be cleared. Monitor is reentrant, so Stop-SessionLogFile taking it
        # again is fine.
        $LockTaken = $false
        try {
            [System.Threading.Monitor]::Enter($State.SyncRoot, [ref]$LockTaken)

            Stop-SessionLogFile

            $State.Path = $null
            $State.Directory = $null
        }
        finally {
            if ($LockTaken) {
                [System.Threading.Monitor]::Exit($State.SyncRoot)
            }
        }

        if (![string]::IsNullOrWhiteSpace($ClosedPath)) {
            "The session log file was closed: {0}" -f $ClosedPath | Write-LogOutput -LogType INFO -SkipDialog
        }

        return $false
    }
    catch {
        # Contained: this runs from the checkbox's event handler, and an ERROR reported the usual way
        # ends in Write-Error under $ErrorActionPreference = Stop, which would throw into the
        # dispatcher's unhandled path and stack dialogs over a checkbox.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        return ($null -ne $Script:SessionLogFile -and $null -ne $Script:SessionLogFile.Writer)
    }
}
