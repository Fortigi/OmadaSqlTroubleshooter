[cmdletbinding()]
param(
    [string[]]$Task = 'default',
    [string[]]$BuildVersion = ""
)
$ErrorActionPreference = "Stop"

if (!(Get-Module -Name Pester -ListAvailable)) { Install-Module -Name Pester -Scope CurrentUser -Force }
if (!(Get-Module -Name psake -ListAvailable)) { Install-Module -Name psake -Scope CurrentUser -Force }
if (!(Get-Module -Name PSDeploy -ListAvailable)) { Install-Module -Name PSDeploy -Scope CurrentUser -Force }
if (!(Get-Module -Name PSScriptAnalyzer -ListAvailable)) { Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force }

Import-Module -Name Pester -Force
Import-Module -Name psake -Force
Import-Module -Name PSDeploy -Force
Import-Module -Name PSScriptAnalyzer -Force

Invoke-psake -buildFile "$PSScriptRoot\psakeBuild.ps1" -taskList $Task -Verbose:$VerbosePreference -parameters @{"BuildVersion"=$BuildVersion}
