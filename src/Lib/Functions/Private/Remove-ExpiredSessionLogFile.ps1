function Remove-ExpiredSessionLogFile {
    <#
    .SYNOPSIS
        Prunes old session log files, by age and then by count.

    .DESCRIPTION
        The "bounded" half of issue #121. Without it an application that writes a log file for every
        session, for the lifetime of every session, is a slow disk leak - which is a worse problem
        than the one the file was added to solve.

        Runs once, at start-up, before the current session's file is opened. Two rules, applied in
        that order:

          * anything whose last write is older than RetentionDays goes;
          * of what is left, only the newest RetentionCount SESSIONS are kept.

        Sessions, not files: a session that reached the size ceiling has several parts, and counting
        files would let one long session use up the entire retention budget and evict every older
        session with it.

        Two things it must never do. It never deletes a file that does not match the name
        Get-SessionLogFileName produces - the log folder is somewhere a user may reasonably keep
        their own notes - and it never deletes the session named by -ExcludeSession, which is the
        one that is starting.

        Failure is not fatal and is not fatal to the session either: a file another process has open,
        or a folder the user cannot write to, means that file stays. The log still gets written.

    .PARAMETER Directory
        The session log folder.

    .PARAMETER RetentionDays
        Sessions whose last write is older than this many days are deleted.

    .PARAMETER RetentionCount
        At most this many sessions are kept.

    .PARAMETER ExcludeSession
        The session key of the session that is starting, which is never deleted. The key is the
        Session capture of Get-SessionLogFileNameExpression, for example "20260914-080503_pid4242".

    .OUTPUTS
        [string[]] the paths that were deleted.

    .NOTES
        No tracer preamble: this runs as part of starting the log file, and the tracer preamble
        would log before there is anywhere to log to.
    #>

    [CmdLetBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [int]$RetentionDays,
        [Parameter(Mandatory = $true)]
        [int]$RetentionCount,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ExcludeSession
    )

    $Deleted = [System.Collections.Generic.List[string]]::new()

    try {
        if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
            return $Deleted.ToArray()
        }

        $NameExpression = Get-SessionLogFileNameExpression

        # The wildcard is what the file system can filter on cheaply; the expression below is what
        # decides whether a candidate really is one of ours. Both have to agree before anything is
        # deleted.
        # A List, not "$Candidate += ...". Array concatenation reallocates the whole array on every
        # element, which is quadratic - and the folder this runs against is precisely the one that
        # grows when pruning has been failing, so the slow path would be the crowded one.
        $Candidate = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($File in (Get-ChildItem -LiteralPath $Directory -Filter (Get-SessionLogFilePattern) -File -ErrorAction SilentlyContinue)) {
            # -match, not "-notmatch ... continue". Both populate $Matches, but reading a capture
            # group after testing for the NEGATIVE reads like a bug even when it is not, and the
            # capture this takes decides which files get deleted together.
            if ($File.Name -match $NameExpression) {
                $Candidate.Add([PSCustomObject]@{
                        Path          = $File.FullName
                        SessionKey    = $Matches["Session"]
                        LastWriteTime = $File.LastWriteTime
                    })
            }
        }

        if ($Candidate.Count -eq 0) {
            return $Deleted.ToArray()
        }

        # A session is as recent as its most recently written part.
        $Session = $Candidate | Group-Object -Property SessionKey | ForEach-Object {
            [PSCustomObject]@{
                SessionKey    = $_.Name
                LastWriteTime = ($_.Group | Measure-Object -Property LastWriteTime -Maximum).Maximum
                File          = $_.Group
            }
        }

        if (![string]::IsNullOrWhiteSpace($ExcludeSession)) {
            $Session = $Session | Where-Object { $_.SessionKey -ne $ExcludeSession }
        }

        $ExpiredBefore = [datetime]::Now.AddDays(-[Math]::Abs($RetentionDays))
        $Expired = @($Session | Where-Object { $_.LastWriteTime -lt $ExpiredBefore })
        $Surviving = @($Session | Where-Object { $_.LastWriteTime -ge $ExpiredBefore } | Sort-Object -Property LastWriteTime -Descending)

        $Excess = @()
        if ($RetentionCount -gt 0 -and $Surviving.Count -gt $RetentionCount) {
            $Excess = $Surviving | Select-Object -Skip $RetentionCount
        }

        foreach ($Doomed in @($Expired) + @($Excess)) {
            foreach ($File in $Doomed.File) {
                try {
                    Remove-Item -LiteralPath $File.Path -Force -ErrorAction Stop
                    $Deleted.Add($File.Path)
                }
                catch {
                    # A file another process still has open stays. Saying so on the console would be
                    # noise about somebody else's session; the tracer is where this belongs.
                    $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: could not prune session log file '{0}': {1}" -f $File.Path, $_.Exception.Message))
                }
            }
        }
    }
    catch {
        # Pruning is housekeeping. A session that cannot prune still gets its log file, which is the
        # point of the feature; failing the start-up path over tidiness would not be.
        $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: session log pruning failed: {0}" -f $_.Exception.Message))
    }

    return $Deleted.ToArray()
}
