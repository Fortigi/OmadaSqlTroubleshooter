function Get-SessionLogFileName {
    <#
    .SYNOPSIS
        Builds the name of a session log file: the active file, or one numbered part of a session.

    .DESCRIPTION
        Two shapes, and only two:

          OmadaSqlTroubleshooter.log                      the part being written right now
          OmadaSqlTroubleshooter_<session>_<part>.log     a finished part, or any part written by a
                                                          second instance that could not use the
                                                          active name

        <session> is the session key New-SessionLogFileSessionKey produces: the session's start time
        as yyyyMMdd-HHmmss, with a letter appended only when another session already holds that
        second. <part> is zero-padded to three digits. Together they make an ordinal sort of the
        folder read as start time, then part.

    .PARAMETER SessionKey
        The session key. Omit it, and Part, for the active file name.

    .PARAMETER Part
        The 1-based part number, 1 to 999.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-SessionLogFileName
        OmadaSqlTroubleshooter.log

    .EXAMPLE
        Get-SessionLogFileName -SessionKey "20260914-080503" -Part 2
        OmadaSqlTroubleshooter_20260914-080503_002.log

    .NOTES
        No tracer preamble: called from the logging path, which must not log about itself.
    #>

    [CmdLetBinding(DefaultParameterSetName = "Active")]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Part")]
        [ValidatePattern('^\d{8}-\d{6}[b-z]?$')]
        [string]$SessionKey,
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Part")]
        [ValidateRange(1, 999)]
        [int]$Part
    )

    if ($PSCmdlet.ParameterSetName -eq "Active") {
        return "OmadaSqlTroubleshooter.log"
    }

    return "OmadaSqlTroubleshooter_{0}_{1:000}.log" -f $SessionKey, $Part
}

function New-SessionLogFileSessionKey {
    <#
    .SYNOPSIS
        Builds the key that names every part of one session.

    .DESCRIPTION
        The start time as yyyyMMdd-HHmmss, and for Index 1 to 25 a letter from "b" to "z" after it.
        A letter rather than a number because a letter sorts after the "_" that follows a plain key:
        "20260914-080503_001" < "20260914-080503b_001" < "20260914-080504_001" holds ordinally, so a
        folder listing and pruning agree on which session came first. A digit suffix would not.

    .PARAMETER StartTime
        When the session started.

    .PARAMETER Index
        0 for the plain key; 1 to 25 when that second is already taken by another session.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [datetime]$StartTime,
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(0, 25)]
        [int]$Index = 0
    )

    $SessionKey = $StartTime.ToString("yyyyMMdd-HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Index -gt 0) {
        $SessionKey = "{0}{1}" -f $SessionKey, [char]([int][char]'a' + $Index)
    }

    return $SessionKey
}

function Test-SessionLogFileSessionKey {
    <#
    .SYNOPSIS
        Tests whether a string is a session key this application writes.

    .DESCRIPTION
        The shape, case-sensitively, and a real date in it. Pruning deletes by this answer, so it is
        deliberately narrower than "looks roughly like a timestamp".

    .PARAMETER SessionKey
        The candidate key.

    .OUTPUTS
        [bool]

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionKey
    )

    if ([string]::IsNullOrEmpty($SessionKey) -or $SessionKey -cnotmatch '^\d{8}-\d{6}[b-z]?$') {
        return $false
    }

    $ParsedStartTime = [datetime]::MinValue
    return [datetime]::TryParseExact($SessionKey.Substring(0, 15), [string[]]@("yyyyMMdd-HHmmss"), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedStartTime)
}

function Get-SessionLogFilePattern {
    <#
    .SYNOPSIS
        The wildcard pattern the file system pre-filters session log files with.

    .DESCRIPTION
        Only a pre-filter. ConvertFrom-SessionLogFileName decides whether a candidate really is one of
        this application's files, because pruning deletes what survives both.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param()

    return "OmadaSqlTroubleshooter*.log"
}

function Get-SessionLogFileNameExpression {
    <#
    .SYNOPSIS
        The expression that matches exactly the names Get-SessionLogFileName produces.

    .DESCRIPTION
        Matched case-sensitively with -cmatch. It matches OmadaSqlTroubleshooter.log and
        OmadaSqlTroubleshooter_<yyyyMMdd-HHmmss>[b-z]_<NNN>.log, and nothing else: not a user's own
        notes, not "OmadaSqlTroubleshooter_backup.log", and not the
        "OmadaSqlTroubleshooter_<start>_pid<id>_<NNN>.log" names of the design that preceded this one,
        which never shipped.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param()

    return '^OmadaSqlTroubleshooter(?:_(?<Session>\d{8}-\d{6}[b-z]?)_(?<Part>\d{3}))?\.log$'
}

function ConvertFrom-SessionLogFileName {
    <#
    .SYNOPSIS
        Splits a session log file name into what it says about the file, or returns nothing for a
        name this application did not write.

    .PARAMETER Name
        A file name, without a directory.

    .OUTPUTS
        [PSCustomObject] with Name, IsActive, SessionKey and Part; nothing for a foreign name.

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    if ($Name -cmatch (Get-SessionLogFileNameExpression)) {
        if ($Name -ceq (Get-SessionLogFileName)) {
            return [PSCustomObject]@{
                Name       = $Name
                IsActive   = $true
                SessionKey = $null
                Part       = 0
            }
        }

        $SessionKey = $Matches["Session"]
        $Part = [int]$Matches["Part"]
        if ($Part -ge 1 -and (Test-SessionLogFileSessionKey -SessionKey $SessionKey)) {
            return [PSCustomObject]@{
                Name       = $Name
                IsActive   = $false
                SessionKey = $SessionKey
                Part       = $Part
            }
        }
    }

    return $null
}

function Get-SessionLogFileInventory {
    <#
    .SYNOPSIS
        Lists this application's session log files in a folder, and only those.

    .PARAMETER Directory
        The session log folder. Used literally; brackets in it are not wildcards.

    .OUTPUTS
        [PSCustomObject[]] ConvertFrom-SessionLogFileName results, each with a Path added.

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory
    )

    $Inventory = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not [System.IO.Directory]::Exists($Directory)) {
        return $Inventory.ToArray()
    }

    foreach ($FilePath in [System.IO.Directory]::EnumerateFiles($Directory, (Get-SessionLogFilePattern))) {
        $Parsed = ConvertFrom-SessionLogFileName -Name ([System.IO.Path]::GetFileName($FilePath))
        if ($null -ne $Parsed) {
            $Parsed | Add-Member -MemberType NoteProperty -Name Path -Value $FilePath
            $Inventory.Add($Parsed)
        }
    }

    return $Inventory.ToArray()
}

function Get-AvailableSessionLogFilePart {
    <#
    .SYNOPSIS
        Finds the first part number, from a starting point, whose file does not exist yet.

    .DESCRIPTION
        Every file this feature creates or renames to is chosen here and then created with
        FileMode.CreateNew or moved without overwrite, so an existing file is never replaced.

    .PARAMETER Directory
        The session log folder.

    .PARAMETER SessionKey
        The session the part belongs to.

    .PARAMETER Part
        The first part number to try.

    .OUTPUTS
        [PSCustomObject] with Path and Part; nothing when every number up to 999 is taken.

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$SessionKey,
        [Parameter(Mandatory = $true, Position = 2)]
        [int]$Part
    )

    for ($Candidate = [Math]::Max(1, $Part); $Candidate -le 999; $Candidate++) {
        $CandidatePath = Join-Path $Directory -ChildPath (Get-SessionLogFileName -SessionKey $SessionKey -Part $Candidate)
        if (-not [System.IO.File]::Exists($CandidatePath)) {
            return [PSCustomObject]@{
                Path = $CandidatePath
                Part = $Candidate
            }
        }
    }

    return $null
}

function Get-SessionLogFileHeader {
    <#
    .SYNOPSIS
        Builds the first line of every session log file part.

    .DESCRIPTION
        The session's identity, recorded in the file itself rather than read from the file system.
        CreationTime cannot be trusted for it: NTFS file-system tunneling hands a file created under a
        name that was renamed or deleted in the last ~15 seconds that earlier file's creation time,
        which is exactly what rotating OmadaSqlTroubleshooter.log does. Every part carries it, so the
        active file can be renamed correctly even when it is the only part of its session left.

        This line reaches disk without passing through Protect-LogMessage, so it must never carry
        anything but these three values. The parameters are typed and the key is validated to make
        that structural: there is no parameter a message could arrive through.

    .PARAMETER SessionKey
        The session key.

    .PARAMETER StartTime
        When the session started.

    .PARAMETER ProcessId
        The process writing the session.

    .OUTPUTS
        [string]

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidatePattern('^\d{8}-\d{6}[b-z]?$')]
        [string]$SessionKey,
        [Parameter(Mandatory = $true, Position = 1)]
        [datetime]$StartTime,
        [Parameter(Mandatory = $true, Position = 2)]
        [int]$ProcessId
    )

    return "OmadaSqlTroubleshooter session log; session {0}; started {1}; process {2}" -f $SessionKey, $StartTime.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture), $ProcessId
}

function Read-SessionLogFileHeader {
    <#
    .SYNOPSIS
        Reads the session key back from the first line of a session log file.

    .DESCRIPTION
        Reads at most the first 512 characters, with sharing that lets the file stay open for writing
        elsewhere. Anything unreadable - no header, a malformed one, a file that vanished, a file
        another program holds exclusively - returns nothing, and the caller decides the fallback.

    .PARAMETER Path
        The file to read.

    .OUTPUTS
        [PSCustomObject] with SessionKey and StartTime (the header's text); nothing when unreadable.

    .NOTES
        No tracer preamble: called from the logging path.
    #>

    [CmdLetBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    try {
        $Stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $Reader = [System.IO.StreamReader]::new($Stream, [System.Text.UTF8Encoding]::new($false))
            $Buffer = [char[]]::new(512)
            $CharacterCount = $Reader.Read($Buffer, 0, $Buffer.Length)
        }
        finally {
            $Stream.Dispose()
        }

        $FirstLine = ([string]::new($Buffer, 0, $CharacterCount) -split "`r?`n", 2)[0]
        if ($FirstLine -cmatch '^OmadaSqlTroubleshooter session log; session (?<Session>\d{8}-\d{6}[b-z]?); started (?<Started>[^;]+); process \d+$') {
            if (Test-SessionLogFileSessionKey -SessionKey $Matches["Session"]) {
                return [PSCustomObject]@{
                    SessionKey = $Matches["Session"]
                    StartTime  = $Matches["Started"]
                }
            }
        }
    }
    catch {
        $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: could not read the session log file header of '{0}': {1}" -f $Path, $_.Exception.Message))
    }

    return $null
}
