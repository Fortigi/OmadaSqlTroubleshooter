PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PsGalleryKey
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11, [Net.SecurityProtocolType]::Tls13

try {
    "Folder tree for SystemDefaultWorkingDirectory:"
    Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object { Write-Host $_.FullName }
}
catch {
    Write-Host "Failed to retrieve directory tree: $_"
}

try {
    "Install OmadaWeb.PS"
    if (!(Get-Module -Name "OmadaWeb.PS" -ListAvailable)) { Install-Module -Name "OmadaWeb.PS" -Scope CurrentUser -Force }
}
catch {
    Write-Error "Failed to install OmadaWeb.PS: $_"
    exit 1
}

try {
    "Publish-Module to PSGallery"
    Publish-Module -Path "$SystemDefaultWorkingDirectory/_OmadaSqlTroubleshooter Build/BuildOutput/OmadaSqlTroubleshooter" -NuGetApiKey "$PsGalleryKey" -Verbose
}
catch {
    Write-Error "Failed to deploy to PowerShell Gallery: $_"
    exit 1
}
