function Confirm-FileHash {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$Path,
        [parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ExpectedSha256,
        [parameter(Mandatory = $true)]
        [string]$ArtifactName,
        [parameter(Mandatory = $false)]
        [string]$SourceUrl
    )

    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    "{0} - Verifying SHA-256 of '{1}'" -f $MyInvocation.MyCommand, $Path | Write-Verbose

    if (-not (Test-Path $Path -PathType Leaf)) {
        "Cannot verify artefact '{0}': the file '{1}' does not exist." -f $ArtifactName, $Path | Write-Error -ErrorAction "Stop"
    }

    # An empty pin would otherwise compare equal to nothing and silently accept any bytes, so it is
    # refused outright rather than treated as "no check requested".
    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        "Artefact '{0}' has no expected SHA-256 in '{1}', so it cannot be verified. Refusing to use it." -f $ArtifactName, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    $ActualSha256 = Get-FileSha256 -Path $Path

    if ($ActualSha256 -ne $ExpectedSha256.ToLowerInvariant()) {
        # Delete first: leaving unverified bytes on disk invites a later code path picking them up.
        Remove-Item -Path $Path -Force -Confirm:$false -ErrorAction SilentlyContinue

        # Removal can fail - a locked file, or a read-only directory. Say which actually happened
        # rather than claiming the bytes are gone: "it was deleted" when it was not is exactly the
        # sentence that stops someone going and removing it by hand.
        if (Test-Path $Path -PathType Leaf) {
            $Disposition = "The file could NOT be deleted and is still on disk at '{0}' - remove it yourself before running this again. It has not been loaded." -f $Path
        }
        else {
            $Disposition = "The file was deleted and has not been loaded."
        }

        "Integrity check FAILED for '{0}' from '{1}'.`r`n  Expected SHA-256: {2}`r`n  Actual SHA-256:   {3}`r`n{4} Either the download was corrupted, or the published artefact no longer matches the version pinned in '{5}'. Do not work around this by editing the lock file - report it at https://github.com/Fortigi/OmadaSqlTroubleshooter/security/advisories/new if you believe the upstream artefact was tampered with." -f $ArtifactName, $SourceUrl, $ExpectedSha256.ToLowerInvariant(), $ActualSha256, $Disposition, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    "{0} - '{1}' matches the pinned SHA-256" -f $MyInvocation.MyCommand, $ArtifactName | Write-Verbose
}
