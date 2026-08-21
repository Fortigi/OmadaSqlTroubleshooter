function Get-LockedArtifact {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$Id
    )

    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    $Lock = Get-DependencyLock

    $Artifact = @($Lock.Artifacts | Where-Object { $_.Id -eq $Id })

    if ($Artifact.Count -eq 0) {
        # Fail closed: an artefact nobody pinned is an artefact nobody can verify.
        "There is no lock entry for artefact '{0}' in '{1}', so it cannot be verified. Refusing to download it." -f $Id, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    if ($Artifact.Count -gt 1) {
        "Artefact '{0}' is listed {1} times in '{2}'. The lock file must hold exactly one entry per artefact." -f $Id, $Artifact.Count, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    return $Artifact[0]
}
