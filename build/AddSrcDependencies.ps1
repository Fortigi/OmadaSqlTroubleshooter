PARAM(
    [switch]$Force
)
$ParentFolder = Split-Path -Path $PSScriptRoot -Parent
& "$PSScriptRoot\RetrieveDependencies.ps1" -DestinationFolder (Join-Path $ParentFolder -ChildPath "src\bin") -Force:$Force.IsPresent
