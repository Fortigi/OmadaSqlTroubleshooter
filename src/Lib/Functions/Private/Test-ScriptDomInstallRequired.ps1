function Test-ScriptDomInstallRequired {
    [CmdletBinding()]
    param()

    # Returns $true when the ScriptDom assembly on disk has to be (re)installed. The mirror of
    # Test-WebView2RuntimeVersion, and it makes the same two checks for the same two reasons.
    #
    # The comparison is against the stamp Install-ScriptDom writes, not against the DLL's
    # ProductVersion: a "-lt" comparison ignores a pin that moves BACKWARDS - a rollback after a bad
    # bump, which is exactly when it most needs to take effect - and leaves the newer, unverified
    # assembly already on disk in use.
    #
    # Matching the version is not on its own enough. Bin is user-writable, so the assembly can be
    # swapped after a verified install without the stamp changing: the download was verified, but
    # nothing had re-checked the bytes since. Comparing the file against the hash recorded at install
    # time closes that, and a mismatch means a re-download rather than a hard failure.
    #
    # No tracer preamble: see Get-DependencyLock. This runs on the startup path.

    try {
        if ([string]::IsNullOrWhiteSpace($Script:ScriptDomPath) -or -not (Test-Path $Script:ScriptDomPath -PathType Leaf)) {
            "No ScriptDom assembly on disk. It will be installed and verified." | Write-Verbose
            return $true
        }

        $Artifact = Get-LockedArtifact -Id "Microsoft.SqlServer.TransactSql.ScriptDom"

        $Stamp = Get-ScriptDomStamp
        if ($null -eq $Stamp) {
            "No usable ScriptDom stamp found. The assembly will be reinstalled and verified." | Write-Verbose
            return $true
        }

        if ($Stamp.Version -ne $Artifact.Version) {
            # Deliberately -ne and not -lt: see above.
            "The installed ScriptDom assembly is stamped {0} but the pinned version is {1}. It will be reinstalled and verified." -f $Stamp.Version, $Artifact.Version | Write-Verbose
            return $true
        }

        if ((Get-FileSha256 -Path $Script:ScriptDomPath) -ne $Stamp.Sha256) {
            "The ScriptDom assembly no longer matches the hash recorded when it was installed. It will be reinstalled and verified." | Write-Warning
            return $true
        }

        "The ScriptDom assembly matches the pinned version {0} and the hash recorded at install time." -f $Artifact.Version | Write-Verbose
        return $false
    }
    catch {
        # Fail towards reinstalling: an unanswerable question about the bytes on disk must not leave
        # them loaded. Install-ScriptDom is the only caller and it degrades to "feature off" if the
        # reinstall then fails, so this cannot break startup.
        "Could not check the installed ScriptDom assembly ({0}). It will be reinstalled and verified." -f $_.Exception.Message | Write-Verbose
        return $true
    }
}
