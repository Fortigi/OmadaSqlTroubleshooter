PARAM(
    [string]$SystemDefaultWorkingDirectory,
    [string]$PsGalleryKey
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12,[Net.SecurityProtocolType]::Tls11,[Net.SecurityProtocolType]::Tls13

try {
    "Folder tree for SystemDefaultWorkingDirectory:"
    Get-ChildItem "$SystemDefaultWorkingDirectory" -Recurse | ForEach-Object { Write-Host $_.FullName }
}
catch {
    Write-Host "Failed to retrieve directory tree: $_"
}

# try {
#     Get-ChildItem "$SystemDefaultWorkingDirectory/_OmadaSqlTroubleshooter" -Filter *.nuspec -Recurse | Copy-Item -Destination "$SystemDefaultWorkingDirectory/_OmadaSqlTroubleshooter Build\BuildOutput\OmadaSqlTroubleshooter" -Force
# }
# catch {
#     Write-Error "Failed to copy nuspec file: $_"
#     exit 1
# }

try {
    "Publish-Module to PSGallery"
    Publish-Module -Path "$SystemDefaultWorkingDirectory/_OmadaSqlTroubleshooter Build/BuildOutput/OmadaSqlTroubleshooter" -NuGetApiKey "$PsGalleryKey" -Verbose
}
catch {
    Write-Error "Failed to deploy to PowerShell Gallery: $_"
    exit 1
}




