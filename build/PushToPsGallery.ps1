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
        $Manifest = Get-ChildItem -Path $SourcePath -Filter '*.psd1' | Select-Object -First 1
        if ($null -eq $Manifest) {
            throw "No .psd1 manifest found in '$SourcePath'."
        }
        "Setting prerelease string '$Prerelease' on $($Manifest.Name)" | Write-Host
        Update-ModuleManifest -Path $Manifest.FullName -Prerelease $Prerelease
    }

    Publish-Module -Path $SourcePath -NuGetApiKey "$PsGalleryKey" -Verbose
}
catch {
    Write-Error "Failed to deploy to PowerShell Gallery: $_"
    exit 1
}




