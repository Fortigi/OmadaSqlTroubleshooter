function Remove-ExcessSessionLogFile {
    <#
    .SYNOPSIS
        Prunes the session log folder to the newest sessions the retention count allows.

    .DESCRIPTION
        The "bounded" half of issue #121, as the maintainer revised it: retention by count only, no
        age rule.

        Sessions, not files. A long session is split into several parts, and counting files would let
        one such session evict every older session in the folder. All parts of a session - its
        numbered parts, plus OmadaSqlTroubleshooter.log when its header names that session - count as
        one, and a session is deleted whole or not at all.

        Order comes from the session key in the name, which is the start time (then the same-second
        letter), compared ordinally. File system dates are not consulted: copying, restoring or
        touching a file changes them.

        What it never does:

          * delete a file whose name is not one of this application's own (ConvertFrom-SessionLogFileName);
          * delete the current session (-CurrentSessionKey);
          * delete a session any of whose files is in use - another instance's running session, or a
            file somebody has open - which is also refused by the share mode the writer uses;
          * delete an OmadaSqlTroubleshooter.log with no readable header: it is either somebody's live
            file or it is rotated, with a key, by the next start.

        It runs after this session's file has been opened, so the count includes the session that is
        running. Failure is housekeeping and never fatal.

    .PARAMETER Directory
        The session log folder.

    .PARAMETER RetentionCount
        At most this many sessions are kept, the current one included.

    .PARAMETER CurrentSessionKey
        The key of the session that is running in this process.

    .OUTPUTS
        [string[]] the paths that were deleted.

    .NOTES
        No tracer preamble: runs as part of starting the log file.
    #>

    [CmdLetBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 2147483647)]
        [int]$RetentionCount,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CurrentSessionKey
    )

    $Deleted = [System.Collections.Generic.List[string]]::new()

    try {
        $SessionFile = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::Ordinal)
        foreach ($Entry in @(Get-SessionLogFileInventory -Directory $Directory)) {
            $SessionKey = $Entry.SessionKey
            if ($Entry.IsActive) {
                $Header = Read-SessionLogFileHeader -Path $Entry.Path
                if ($null -eq $Header) {
                    continue
                }

                $SessionKey = $Header.SessionKey
            }

            if (-not $SessionFile.ContainsKey($SessionKey)) {
                $SessionFile[$SessionKey] = [System.Collections.Generic.List[string]]::new()
            }

            $SessionFile[$SessionKey].Add($Entry.Path)
        }

        $OrderedSessionKey = [System.Collections.Generic.List[string]]::new([string[]]@($SessionFile.Keys))
        $OrderedSessionKey.Sort([System.StringComparer]::Ordinal)

        $ExcessCount = $OrderedSessionKey.Count - $RetentionCount
        foreach ($SessionKey in $OrderedSessionKey) {
            if ($ExcessCount -le 0) {
                break
            }

            if ($SessionKey -ceq $CurrentSessionKey) {
                continue
            }

            $InUseFile = @($SessionFile[$SessionKey] | Where-Object { Test-SessionLogFileInUse -Path $_ })
            if ($InUseFile.Count -gt 0) {
                $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: kept session {0}, which is in use" -f $SessionKey))
                continue
            }

            $AllDeleted = $true
            foreach ($FilePath in $SessionFile[$SessionKey]) {
                try {
                    [System.IO.File]::Delete($FilePath)
                    $Deleted.Add($FilePath)
                }
                catch {
                    $AllDeleted = $false
                    $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: could not prune session log file '{0}': {1}" -f $FilePath, $_.Exception.Message))
                }
            }

            if ($AllDeleted) {
                $ExcessCount = $ExcessCount - 1
            }
        }
    }
    catch {
        $Script:Tracer::WriteLine(("OmadaSqlTroubleshooter: session log pruning failed: {0}" -f $_.Exception.Message))
    }

    return $Deleted.ToArray()
}

function Test-SessionLogFileInUse {
    <#
    .SYNOPSIS
        Tests whether any process has a file open.

    .DESCRIPTION
        Opens the file with FileShare.None and closes it at once. That open is refused while any other
        handle is open, whatever that handle shares, so a session still being written - by this
        application or by anything else holding one of its files - reads as in use. A file that
        cannot be checked at all also reads as in use, because the answer decides a delete.

    .PARAMETER Path
        The file to test.

    .OUTPUTS
        [bool]

    .NOTES
        No tracer preamble: runs as part of starting the log file.
    #>

    [CmdLetBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    try {
        $Stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        $Stream.Dispose()
        return $false
    }
    catch {
        return $true
    }
}
