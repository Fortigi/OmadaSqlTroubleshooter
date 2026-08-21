PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PsGalleryKey,
    [string]$BuildPath,
    [string]$Prerelease = ""
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls13

try {
    "Folder tree for SystemDefaultWorkingDirectory:" | Write-Host
    Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object { Write-Host $_.FullName }
}
catch {
    Write-Host "Failed to retrieve directory tree: $_"
}

try {
    "Publish-Module to PSGallery" | Write-Host
    $SourcePath = "{0}/buildoutput/{1}" -f $SystemDefaultWorkingDirectory, $BuildPath.TrimStart('/')

    if (-not [string]::IsNullOrWhiteSpace($Prerelease)) {
        # Select the module manifest by name, never "the first .psd1". The package also contains
        # DependencyLock.psd1, which sorts before OmadaSqlTroubleShooter.psd1 - picking the first
        # match would hand the lock file to Update-ModuleManifest below and rewrite it as a module
        # manifest, leaving the published module unable to verify any download.
        $ManifestName = '{0}.psd1' -f (Split-Path $SourcePath -Leaf)
        $Manifest = Get-ChildItem -Path $SourcePath -Filter '*.psd1' |
            Where-Object { $_.Name -eq $ManifestName } |
            Select-Object -First 1
        if ($null -eq $Manifest) {
            throw "No module manifest '$ManifestName' found in '$SourcePath'."
        }

        # PSGallery requires exactly 3-part version for pre-release packages (SemVer).
        # Drop the 4th part (run number) — it is already encoded in the Prerelease string
        # (e.g. 'nightly15'), giving a final version like 2026.7.3-nightly15.
        $Parts = ($ManifestData = Import-PowerShellDataFile -Path $Manifest.FullName).ModuleVersion -split '\.'
        if ($Parts.Count -eq 4) {
            $ThreePartVersion = '{0}.{1}.{2}' -f $Parts[0], $Parts[1], $Parts[2]
            "Converting version $($ManifestData.ModuleVersion) to 3-part prerelease version $ThreePartVersion" | Write-Host
            Update-ModuleManifest -Path $Manifest.FullName -ModuleVersion $ThreePartVersion -Prerelease $Prerelease
        }
        else {
            "Setting prerelease string '$Prerelease' on $($Manifest.Name)" | Write-Host
            Update-ModuleManifest -Path $Manifest.FullName -Prerelease $Prerelease
        }
    }

    Publish-Module -Path $SourcePath -NuGetApiKey "$PsGalleryKey" -Verbose
}
catch {
    Write-Error "Failed to deploy to PowerShell Gallery: $_"
    exit 1
}




