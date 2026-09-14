function Open-SessionLogFile {
    <#
    .SYNOPSIS
        Rotates the previous session's active file if it is free, and opens this session's first part.

    .DESCRIPTION
        The start-up half of the naming the maintainer set for issue #121:

          1. If OmadaSqlTroubleshooter.log exists, try to rename it to the next numbered part of the
             session its header names (Move-SessionLogFileToPart).
          2. If it is still there afterwards, something holds it open - another running instance,
             because no instance shares Delete on the file it writes - and it is not touched again.
          3. Choose a session key no other session in the folder holds.
          4. Create OmadaSqlTroubleshooter.log if the name is free; otherwise, as a second instance,
             create OmadaSqlTroubleshooter_<session>_001.log.

        The caller holds Enter-SessionLogFileMutex around this, so steps 1 to 4 are not interleaved
        with another instance doing the same.

    .PARAMETER Directory
        The session log folder, which must exist.

    .PARAMETER StartTime
        When this session started.

    .PARAMETER ProcessId
        This process's id, for the header.

    .OUTPUTS
        [PSCustomObject] with Path, Writer, BytesWritten, SessionKey, Part, UsesActiveName and
        RotatedPath (the previous active file's new name, or nothing).

    .NOTES
        No tracer preamble: runs while the log file is being set up.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [datetime]$StartTime,
        [Parameter(Mandatory = $true)]
        [int]$ProcessId
    )

    $ActivePath = Join-Path $Directory -ChildPath (Get-SessionLogFileName)
    $RotatedPath = $null
    $ActiveInUse = $false

    if ([System.IO.File]::Exists($ActivePath)) {
        $RotatedPath = Move-SessionLogFileToPart -Directory $Directory
        if ($null -eq $RotatedPath -and [System.IO.File]::Exists($ActivePath)) {
            $ActiveInUse = $true
        }
    }

    $SessionKey = Get-UnusedSessionLogFileSessionKey -Directory $Directory -StartTime $StartTime
    if ($null -eq $SessionKey) {
        throw "every session key for {0} is already taken" -f $StartTime.ToString("yyyyMMdd-HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if (-not $ActiveInUse) {
        try {
            $Opened = Open-SessionLogFileWriter -Path $ActivePath -SessionKey $SessionKey -StartTime $StartTime -ProcessId $ProcessId
            return [PSCustomObject]@{
                Path           = $ActivePath
                Writer         = $Opened.Writer
                BytesWritten   = $Opened.BytesWritten
                SessionKey     = $SessionKey
                Part           = 1
                UsesActiveName = $true
                RotatedPath    = $RotatedPath
            }
        }
        catch {
            # CreateNew refused. If the name now exists, somebody else took it and this session is a
            # second instance after all; if it does not, the failure is real and belongs to the caller.
            if (-not [System.IO.File]::Exists($ActivePath)) {
                throw
            }
        }
    }

    $FirstPart = Get-AvailableSessionLogFilePart -Directory $Directory -SessionKey $SessionKey -Part 1
    if ($null -eq $FirstPart) {
        throw "no part number is left for session {0}" -f $SessionKey
    }

    $Opened = Open-SessionLogFileWriter -Path $FirstPart.Path -SessionKey $SessionKey -StartTime $StartTime -ProcessId $ProcessId
    return [PSCustomObject]@{
        Path           = $FirstPart.Path
        Writer         = $Opened.Writer
        BytesWritten   = $Opened.BytesWritten
        SessionKey     = $SessionKey
        Part           = $FirstPart.Part
        UsesActiveName = $false
        RotatedPath    = $RotatedPath
    }
}

function Move-SessionLogFileToPart {
    <#
    .SYNOPSIS
        Renames a leftover OmadaSqlTroubleshooter.log to the next numbered part of its own session.

    .DESCRIPTION
        The session comes from the file's header, never from its CreationTime (see
        Get-SessionLogFileHeader). The part number is one past the highest part of that session
        already in the folder: 001 for a session that never split.

        A file with no readable header - written by hand, truncated, or left by something else under
        that name - falls back to its LastWriteTime for the key, choosing a letter if that second
        belongs to another session so its file cannot join a session that is not its own.

        The rename is one attempt, without overwrite. If it is refused, the file is in use - or cannot
        be renamed for another reason - and in every such case it is left exactly where it is.

    .PARAMETER Directory
        The session log folder.

    .OUTPUTS
        [string] the new path, or nothing when the file was not renamed.

    .NOTES
        No tracer preamble: runs while the log file is being set up.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory
    )

    $ActivePath = Join-Path $Directory -ChildPath (Get-SessionLogFileName)
    if (-not [System.IO.File]::Exists($ActivePath)) {
        return $null
    }

    $Header = Read-SessionLogFileHeader -Path $ActivePath
    if ($null -ne $Header) {
        $SessionKey = $Header.SessionKey
    }
    else {
        $SessionKey = Get-UnusedSessionLogFileSessionKey -Directory $Directory -StartTime ([System.IO.File]::GetLastWriteTime($ActivePath))
        if ($null -eq $SessionKey) {
            return $null
        }
    }

    $HighestPart = (@(Get-SessionLogFileInventory -Directory $Directory) | Where-Object { -not $_.IsActive -and $_.SessionKey -ceq $SessionKey } | Measure-Object -Property Part -Maximum).Maximum
    $Target = Get-AvailableSessionLogFilePart -Directory $Directory -SessionKey $SessionKey -Part ([int]$HighestPart + 1)
    if ($null -eq $Target) {
        return $null
    }

    try {
        [System.IO.File]::Move($ActivePath, $Target.Path)
        return $Target.Path
    }
    catch {
        $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: left '{0}' in place: {1}" -f $ActivePath, $_.Exception.Message))
    }

    return $null
}

function Get-UnusedSessionLogFileSessionKey {
    <#
    .SYNOPSIS
        Chooses a session key for a start time that no session in the folder already holds.

    .DESCRIPTION
        Taken keys are those in the numbered part names, plus the key in the header of
        OmadaSqlTroubleshooter.log when that file is present - a running session that has not split
        yet has no numbered part to show for itself. The plain key is preferred; then "b" to "z".

    .PARAMETER Directory
        The session log folder.

    .PARAMETER StartTime
        The start time the key is built from.

    .OUTPUTS
        [string] the key, or nothing when all 26 are taken.

    .NOTES
        No tracer preamble: runs while the log file is being set up.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory,
        [Parameter(Mandatory = $true, Position = 1)]
        [datetime]$StartTime
    )

    $TakenKey = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($Entry in @(Get-SessionLogFileInventory -Directory $Directory)) {
        if ($Entry.IsActive) {
            $Header = Read-SessionLogFileHeader -Path $Entry.Path
            if ($null -ne $Header) {
                [void]$TakenKey.Add($Header.SessionKey)
            }
        }
        else {
            [void]$TakenKey.Add($Entry.SessionKey)
        }
    }

    foreach ($Index in 0..25) {
        $Candidate = New-SessionLogFileSessionKey -StartTime $StartTime -Index $Index
        if (-not $TakenKey.Contains($Candidate)) {
            return $Candidate
        }
    }

    return $null
}
