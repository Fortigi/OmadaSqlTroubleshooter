function Invoke-DownloadFile {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$ArtifactId,
        [parameter(Mandatory = $false)]
        [validateScript({ Test-Path (Split-Path $_) -PathType 'Container' })]
        $OutputFile
    )

    # Every binary the module loads passes through here, so this is where integrity is enforced: an
    # artefact that is not in the lock file is never fetched, and the bytes are verified against the
    # pinned SHA-256 before the path is handed back to be expanded or copied into Bin.
    #
    # There is deliberately no -DownloadUrl parameter. OmadaWeb.PS has one because msedgedriver.exe
    # must match the Edge build installed on the machine and so cannot be pinned; nothing in this
    # module has that problem. Leaving the parameter out makes "download an arbitrary URL"
    # structurally unrepresentable rather than merely refused at runtime.
    #
    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    $Artifact = Get-LockedArtifact -Id $ArtifactId

    if ($Artifact.Verification -ne "Sha256") {
        "Artefact '{0}' is declared as '{1}' in '{2}', but this module only implements 'Sha256' verification. Refusing to download it." -f $ArtifactId, $Artifact.Verification, $Script:DependencyLockPath | Write-Error -ErrorAction "Stop"
    }

    $DownloadUrl = $Artifact.Url

    "{0} - Downloading artefact '{1}' from URL: {2}" -f $MyInvocation.MyCommand, $ArtifactId, $DownloadUrl | Write-Verbose

    try {
        if ([String]::IsNullOrWhiteSpace($OutputFile)) {
            $OutputFile = [System.IO.Path]::GetTempFileName()
        }
        $OutputFile | Write-Verbose

        Save-RemoteFile -DownloadUrl $DownloadUrl -OutputFile $OutputFile
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }

    # Throws and deletes the file on mismatch, so nothing downstream ever sees unverified bytes.
    Confirm-FileHash -Path $OutputFile -ExpectedSha256 $Artifact.Sha256 -ArtifactName ("{0} {1}" -f $ArtifactId, $Artifact.Version).Trim() -SourceUrl $DownloadUrl

    return $OutputFile
}
